# -----------------------------------------------------------------------------
# CloudWatch Logs
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "grafana" {
  name              = "/ecs/${var.environment}-${local.app_name}"
  retention_in_days = 1
  skip_destroy      = false

  tags = merge(var.tags, { Name = "/ecs/${var.environment}-${local.app_name}" })
}
