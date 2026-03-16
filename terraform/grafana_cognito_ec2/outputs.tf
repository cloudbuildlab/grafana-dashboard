# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "web_url" {
  description = "URL to Grafana (HTTPS via Route 53)."
  value       = "https://${trimsuffix(aws_route53_record.grafana.fqdn, ".")}"
}

output "instance_id" {
  description = "EC2 instance ID (for debugging or Session Manager)."
  value       = aws_instance.grafana.id
}

output "instance_private_ip" {
  description = "Private IP of the Grafana EC2 instance."
  value       = aws_instance.grafana.private_ip
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
