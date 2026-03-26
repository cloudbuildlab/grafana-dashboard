# -----------------------------------------------------------------------------
# Lambda: bootstrap S3 changes on datasource/promtail prefixes → Grafana-only
# force new deployment so bootstrap re-syncs from S3 on the new task.
# Dashboard changes (grafana/dashboards/) are handled by the sync Lambda in
# sync_task.tf and do NOT trigger a task replacement.
# Loki is never restarted by any bootstrap S3 event.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "bootstrap_roll_lambda" {
  count = var.enable_bootstrap_roll_lambda ? 1 : 0
  name  = "${var.environment}-${local.app_name}-bootstrap-roll-lambda"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-bootstrap-roll-lambda" })
}

resource "aws_iam_role_policy_attachment" "bootstrap_roll_lambda_basic" {
  count      = var.enable_bootstrap_roll_lambda ? 1 : 0
  role       = aws_iam_role.bootstrap_roll_lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "bootstrap_roll_ecs" {
  count = var.enable_bootstrap_roll_lambda ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    # Grafana only — Loki is never restarted by provisioning S3 events.
    resources = [aws_ecs_service.grafana.arn]
  }
}

resource "aws_iam_role_policy" "bootstrap_roll_ecs" {
  count  = var.enable_bootstrap_roll_lambda ? 1 : 0
  name   = "ecs-roll"
  role   = aws_iam_role.bootstrap_roll_lambda[0].id
  policy = data.aws_iam_policy_document.bootstrap_roll_ecs[0].json
}

resource "aws_cloudwatch_log_group" "bootstrap_roll_lambda" {
  count             = var.enable_bootstrap_roll_lambda ? 1 : 0
  name              = "/aws/lambda/${var.environment}-${local.app_name}-bootstrap-roll"
  retention_in_days = 14
  skip_destroy      = false

  tags = merge(var.tags, { Name = "/aws/lambda/${var.environment}-${local.app_name}-bootstrap-roll" })
}

resource "aws_lambda_function" "bootstrap_roll" {
  count            = var.enable_bootstrap_roll_lambda ? 1 : 0
  function_name    = "${var.environment}-${local.app_name}-bootstrap-roll"
  description      = "On bootstrap S3 changes, force new ECS deployment so provisioning sync runs"
  role             = aws_iam_role.bootstrap_roll_lambda[0].arn
  filename         = data.archive_file.bootstrap_roll_zip.output_path
  source_code_hash = data.archive_file.bootstrap_roll_zip.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.14"
  timeout          = 60

  environment {
    variables = {
      ECS_CLUSTER_ARN   = var.ecs_cluster_arn
      ECS_SERVICE_NAMES = aws_ecs_service.grafana.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.bootstrap_roll_lambda_basic,
    aws_cloudwatch_log_group.bootstrap_roll_lambda,
    aws_ecs_service.grafana,
  ]

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-bootstrap-roll" })
}

resource "aws_lambda_permission" "bootstrap_roll_s3" {
  count         = var.enable_bootstrap_roll_lambda ? 1 : 0
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bootstrap_roll[0].function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.bootstrap.arn
}

# Single aws_s3_bucket_notification per bucket. Combines:
#   - grafana/datasources/ and promtail/ → roll Lambda (Grafana forceNewDeployment)
#   - grafana/dashboards/ → sync Lambda (RunTask, no restart)
resource "aws_s3_bucket_notification" "bootstrap_roll" {
  bucket = aws_s3_bucket.bootstrap.id

  # Datasource changes: force new Grafana deployment so bootstrap re-syncs from S3.
  dynamic "lambda_function" {
    for_each = var.enable_bootstrap_roll_lambda ? ["grafana/datasources/", "promtail/"] : []
    content {
      lambda_function_arn = aws_lambda_function.bootstrap_roll[0].arn
      events              = ["s3:ObjectCreated:*"]
      filter_prefix       = lambda_function.value
    }
  }

  # Dashboard changes: trigger sync RunTask; Grafana file poller handles reload.
  lambda_function {
    lambda_function_arn = aws_lambda_function.dashboard_sync.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "grafana/dashboards/"
  }

  # Keep explicit permission dependencies to avoid eventual consistency issues.
  depends_on = [
    aws_lambda_permission.dashboard_sync_s3,
    aws_lambda_permission.bootstrap_roll_s3,
  ]
}
