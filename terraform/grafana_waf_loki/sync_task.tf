# -----------------------------------------------------------------------------
# Dashboard sync: S3 ObjectCreated on grafana/dashboards/ → Lambda → ecs:RunTask
# The sync task copies S3 dashboard JSON onto EFS; Grafana's file poller picks
# up changes within updateIntervalSeconds (10s) without any task replacement.
# -----------------------------------------------------------------------------

data "archive_file" "dashboard_sync_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/dashboard_sync/handler.py"
  output_path = "${path.module}/.build/dashboard_sync.zip"
}

resource "aws_cloudwatch_log_group" "dashboard_sync_lambda" {
  name              = "/aws/lambda/${var.environment}-${local.app_name}-dashboard-sync"
  retention_in_days = 14
  skip_destroy      = false

  tags = merge(var.tags, { Name = "/aws/lambda/${var.environment}-${local.app_name}-dashboard-sync" })
}

resource "aws_lambda_function" "dashboard_sync" {
  function_name    = "${var.environment}-${local.app_name}-dashboard-sync"
  description      = "On grafana/dashboards/ S3 changes, run the ECS sync task to update EFS"
  role             = aws_iam_role.dashboard_sync_lambda.arn
  filename         = data.archive_file.dashboard_sync_zip.output_path
  source_code_hash = data.archive_file.dashboard_sync_zip.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.14"
  timeout          = 120

  environment {
    variables = {
      ECS_CLUSTER_ARN = var.ecs_cluster_arn
      # Family only: RunTask uses latest ACTIVE revision (avoids stale :N ARN after each replace).
      SYNC_TASK_DEFINITION = aws_ecs_task_definition.grafana_sync.family
      SUBNET_IDS           = join(",", var.private_subnet_ids)
      SECURITY_GROUP_IDS   = aws_security_group.sync_task.id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.dashboard_sync_lambda_basic,
    aws_cloudwatch_log_group.dashboard_sync_lambda,
    aws_ecs_task_definition.grafana_sync,
  ]

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-dashboard-sync" })
}

resource "aws_lambda_permission" "dashboard_sync_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dashboard_sync.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.bootstrap.arn
}
