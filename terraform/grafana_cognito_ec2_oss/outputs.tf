# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "web_url" {
  description = "URL to Grafana (HTTPS via Route 53). Use this for Cognito login."
  value       = "https://${trimsuffix(aws_route53_record.grafana_oss.fqdn, ".")}"
}

output "alb_http_url" {
  description = "HTTP URL via ALB DNS (ACM cert does not cover *.elb.amazonaws.com). Quick check before DNS; not for OAuth."
  value       = "http://${aws_lb.app_oss.dns_name}"
}

output "instance_id" {
  description = "EC2 instance ID (for debugging or Session Manager)."
  value       = aws_instance.grafana_oss.id
}

output "instance_private_ip" {
  description = "Private IP of the Grafana EC2 instance."
  value       = aws_instance.grafana_oss.private_ip
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID for Grafana SSO."
  value       = aws_cognito_user_pool.grafana_oss.id
}

output "cognito_user_pool_domain" {
  description = "Cognito user pool domain (for hosted UI / docs)."
  value       = "${aws_cognito_user_pool_domain.grafana_oss.domain}.auth.${data.aws_region.current_oss.id}.amazoncognito.com"
}

output "cognito_app_client_id" {
  description = "Cognito app client ID (for reference)."
  value       = aws_cognito_user_pool_client.grafana_oss.id
}
