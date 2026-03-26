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
# Loki ruler also needs PutObject/DeleteObject to persist recording rule state.
data "aws_iam_policy_document" "ecs_task_bootstrap_s3" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.bootstrap.arn, "${aws_s3_bucket.bootstrap.arn}/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.bootstrap.arn}/loki/*"]
  }
}

resource "aws_iam_role_policy" "ecs_task_bootstrap_s3" {
  name   = "${var.environment}-${local.app_name}-bootstrap-s3"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_bootstrap_s3.json
}

# Grafana task: mount EFS (read + write for bootstrap to populate provisioning dirs).
data "aws_iam_policy_document" "ecs_task_efs" {
  statement {
    effect = "Allow"
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
    ]
    resources = [
      aws_efs_file_system.grafana.arn,
      aws_efs_access_point.grafana.arn,
    ]
  }
}

resource "aws_iam_role_policy" "ecs_task_efs" {
  name   = "${var.environment}-${local.app_name}-efs"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_efs.json
}

# ECS infrastructure role used by ECS to manage task-attached EBS volumes.
resource "aws_iam_role" "ecs_ebs" {
  name = "${var.environment}-${local.app_name}-ecs-ebs"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-ecs-ebs" })
}

resource "aws_iam_role_policy_attachment" "ecs_ebs_volumes" {
  role       = aws_iam_role.ecs_ebs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForVolumes"
}

# -----------------------------------------------------------------------------
# IAM — Dashboard sync task (separate RunTask, not a service)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "sync_task_execution" {
  name = "${var.environment}-${local.app_name}-sync-execution"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-sync-execution" })
}

resource "aws_iam_role_policy_attachment" "sync_task_execution" {
  role       = aws_iam_role.sync_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "sync_task" {
  name = "${var.environment}-${local.app_name}-sync-task"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-sync-task" })
}

data "aws_iam_policy_document" "sync_task_inline" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.bootstrap.arn, "${aws_s3_bucket.bootstrap.arn}/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
    ]
    resources = [
      aws_efs_file_system.grafana.arn,
      aws_efs_access_point.grafana.arn,
    ]
  }
}

resource "aws_iam_role_policy" "sync_task_inline" {
  name   = "s3-efs"
  role   = aws_iam_role.sync_task.id
  policy = data.aws_iam_policy_document.sync_task_inline.json
}

# Lambda that invokes the sync RunTask on dashboard S3 events.
resource "aws_iam_role" "dashboard_sync_lambda" {
  name = "${var.environment}-${local.app_name}-dashboard-sync-lambda"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-dashboard-sync-lambda" })
}

resource "aws_iam_role_policy_attachment" "dashboard_sync_lambda_basic" {
  role       = aws_iam_role.dashboard_sync_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "dashboard_sync_lambda_ecs" {
  # RunTask must be allowed for every revision; a pinned :N ARN breaks after each task-def replace.
  statement {
    effect    = "Allow"
    actions   = ["ecs:RunTask"]
    resources = ["${aws_ecs_task_definition.grafana_sync.arn_without_revision}:*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["ecs:DescribeTasks"]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.sync_task_execution.arn, aws_iam_role.sync_task.arn]
  }
}

resource "aws_iam_role_policy" "dashboard_sync_lambda_ecs" {
  name   = "ecs-run-task"
  role   = aws_iam_role.dashboard_sync_lambda.id
  policy = data.aws_iam_policy_document.dashboard_sync_lambda_ecs.json
}

# -----------------------------------------------------------------------------
# IAM — WAF worker execution + task roles
# -----------------------------------------------------------------------------
resource "aws_iam_role" "waf_worker_execution" {
  name = "${var.environment}-${local.app_name}-waf-worker-execution"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-waf-worker-execution" })
}

resource "aws_iam_role_policy_attachment" "waf_worker_execution_ecs" {
  role       = aws_iam_role.waf_worker_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "waf_worker_task" {
  name = "${var.environment}-${local.app_name}-waf-worker-task"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-waf-worker-task" })
}

data "aws_iam_policy_document" "waf_worker_inline" {
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

resource "aws_iam_role_policy" "waf_worker_inline" {
  name   = "s3-sqs"
  role   = aws_iam_role.waf_worker_task.id
  policy = data.aws_iam_policy_document.waf_worker_inline.json
}
