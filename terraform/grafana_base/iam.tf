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
