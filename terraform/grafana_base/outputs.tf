# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "web_url" {
  description = "URL to Grafana (via ALB)."
  value       = "http://${aws_lb.app.dns_name}"
}

output "log_group_grafana" {
  value = aws_cloudwatch_log_group.grafana.name
}
