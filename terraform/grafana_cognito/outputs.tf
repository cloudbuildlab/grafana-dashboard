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

output "cognito_user_pool_id" {
  description = "Cognito user pool ID for Grafana SSO."
  value       = aws_cognito_user_pool.grafana.id
}

output "cognito_user_pool_domain" {
  description = "Cognito user pool domain (for hosted UI / docs)."
  value       = "${aws_cognito_user_pool_domain.grafana.domain}.auth.${data.aws_region.current.id}.amazoncognito.com"
}

output "cognito_app_client_id" {
  description = "Cognito app client ID (for reference)."
  value       = aws_cognito_user_pool_client.grafana.id
}
