# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "web_url" {
  description = "URL to Grafana (HTTPS via Route 53)."
  value       = "https://${trimsuffix(aws_route53_record.grafana.fqdn, ".")}"
}

output "log_group_grafana" {
  description = "CloudWatch log group for Grafana container logs."
  value       = aws_cloudwatch_log_group.grafana.name
}

output "efs_id" {
  description = "EFS file system ID used for Grafana data (backup/restore)."
  value       = aws_efs_file_system.grafana.id
}
