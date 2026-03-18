# -----------------------------------------------------------------------------
# Local values
# -----------------------------------------------------------------------------
locals {
  app_name = "grafana"
  # Distinct from grafana_cognito_ec2 when both run in the same account/VPC
  aws_name_prefix   = "${var.environment}-${local.app_name}-oss"
  my_public_ip_cidr = "${trimspace(data.http.my_public_ip_oss.response_body)}/32"
  alb_ingress_cidrs = length(var.alb_ingress_cidrs) > 0 ? var.alb_ingress_cidrs : [local.my_public_ip_cidr]

  # Flatten cognito_users: list of { email, name, group } for aws_cognito_user and outputs
  flat_cognito_users = length(var.cognito_users) > 0 ? flatten([
    for group_name, users in var.cognito_users : [
      for u in users : merge(u, { group = group_name })
    ]
  ]) : []

  grafana_fqdn       = trimsuffix(aws_route53_record.grafana_oss.fqdn, ".")
  cognito_domain_url = "https://${aws_cognito_user_pool_domain.grafana_oss.domain}.auth.${data.aws_region.current_oss.id}.amazoncognito.com"

  # User data for EC2: install Docker, local data dir, fetch SSM secrets, run Grafana container
  user_data = base64encode(templatefile("${path.module}/scripts/user_data.sh.tpl", {
    aws_region         = data.aws_region.current_oss.id
    ssm_cognito_secret = aws_ssm_parameter.cognito_client_secret_oss.name
    ssm_admin_password = var.grafana_admin_password != "" ? aws_ssm_parameter.grafana_admin_password_oss[0].name : ""
    has_admin_password = var.grafana_admin_password != ""
    grafana_fqdn       = local.grafana_fqdn
    cognito_domain_url = local.cognito_domain_url
    cognito_client_id  = aws_cognito_user_pool_client.grafana_oss.id
    grafana_port       = var.grafana_port
    grafana_image      = var.grafana_image
  }))
}
