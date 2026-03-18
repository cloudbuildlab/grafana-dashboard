# -----------------------------------------------------------------------------
# SSM Parameter Store (secrets; EC2 user data fetches at boot)
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "grafana_admin_password_oss" {
  count = var.grafana_admin_password != "" ? 1 : 0

  name  = "/ec2/${local.aws_name_prefix}/GF_SECURITY_ADMIN_PASSWORD"
  type  = "SecureString"
  value = var.grafana_admin_password

  tags = merge(var.tags, { Name = "/ec2/${local.aws_name_prefix}/GF_SECURITY_ADMIN_PASSWORD" })
}

resource "aws_ssm_parameter" "cognito_client_secret_oss" {
  name  = "/ec2/${local.aws_name_prefix}/COGNITO_CLIENT_SECRET"
  type  = "SecureString"
  value = aws_cognito_user_pool_client.grafana_oss.client_secret

  tags = merge(var.tags, { Name = "/ec2/${local.aws_name_prefix}/COGNITO_CLIENT_SECRET" })
}
