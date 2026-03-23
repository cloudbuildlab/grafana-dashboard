# -----------------------------------------------------------------------------
# IAM Roles for ECS
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_execution" {
  name = "${var.environment}-${local.app_name}-ecs-execution"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-ecs-execution" })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_execution_ssm" {
  count = var.grafana_admin_password != "" ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [aws_ssm_parameter.grafana_admin_password[0].arn]
  }
}

resource "aws_iam_role_policy" "ecs_execution_ssm" {
  count  = var.grafana_admin_password != "" ? 1 : 0
  name   = "${var.environment}-${local.app_name}-ssm"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.ecs_execution_ssm[0].json
}

resource "aws_iam_role" "ecs_task" {
  name = "${var.environment}-${local.app_name}-ecs-task"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-ecs-task" })
}

# Bootstrap init container uses task-role credentials to sync from S3.
data "aws_iam_policy_document" "ecs_task_bootstrap_s3" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.bootstrap.arn, "${aws_s3_bucket.bootstrap.arn}/*"]
  }
}

resource "aws_iam_role_policy" "ecs_task_bootstrap_s3" {
  name   = "${var.environment}-${local.app_name}-bootstrap-s3"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_bootstrap_s3.json
}

# -----------------------------------------------------------------------------
# IAM — WAF Lambda execution role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "waf_lambda" {
  name = "${var.environment}-${local.app_name}-waf-lambda"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-waf-lambda" })
}

resource "aws_iam_role_policy_attachment" "waf_lambda_basic" {
  role       = aws_iam_role.waf_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "waf_lambda_vpc" {
  role       = aws_iam_role.waf_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "waf_lambda_inline" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${data.aws_s3_bucket.waf_logs.arn}/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [aws_sqs_queue.waf_ingest.arn]
  }
}

resource "aws_iam_role_policy" "waf_lambda_inline" {
  name   = "s3-sqs"
  role   = aws_iam_role.waf_lambda.id
  policy = data.aws_iam_policy_document.waf_lambda_inline.json
}
