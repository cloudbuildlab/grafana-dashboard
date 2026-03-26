# -----------------------------------------------------------------------------
# CloudWatch Logs (retention / naming aligned with grafana_base)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "bootstrap" {
  name              = "/ecs/${var.environment}-${local.app_name}-bootstrap"
  retention_in_days = 1
  skip_destroy      = false

  tags = merge(var.tags, { Name = "/ecs/${var.environment}-${local.app_name}-bootstrap" })
}

resource "aws_cloudwatch_log_group" "loki" {
  name              = "/ecs/${var.environment}-${local.app_name}-loki"
  retention_in_days = 1
  skip_destroy      = false

  tags = merge(var.tags, { Name = "/ecs/${var.environment}-${local.app_name}-loki" })
}

resource "aws_cloudwatch_log_group" "grafana" {
  name              = "/ecs/${var.environment}-${local.app_name}-grafana"
  retention_in_days = 1
  skip_destroy      = false

  tags = merge(var.tags, { Name = "/ecs/${var.environment}-${local.app_name}-grafana" })
}

resource "aws_cloudwatch_log_group" "promtail" {
  name              = "/ecs/${var.environment}-${local.app_name}-promtail"
  retention_in_days = 1
  skip_destroy      = false

  tags = merge(var.tags, { Name = "/ecs/${var.environment}-${local.app_name}-promtail" })
}

