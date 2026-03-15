# -----------------------------------------------------------------------------
# SSM Parameter Store (secrets; ECS task reads at runtime)
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "grafana_admin_password" {
  count = var.grafana_admin_password != "" ? 1 : 0

  name  = "/ecs/${var.environment}-${local.app_name}/GF_SECURITY_ADMIN_PASSWORD"
  type  = "SecureString"
  value = var.grafana_admin_password

  tags = merge(var.tags, { Name = "/ecs/${var.environment}-${local.app_name}/GF_SECURITY_ADMIN_PASSWORD" })
}

resource "aws_ssm_parameter" "cognito_client_secret" {
  name  = "/ecs/${var.environment}-${local.app_name}/COGNITO_CLIENT_SECRET"
  type  = "SecureString"
  value = aws_cognito_user_pool_client.grafana.client_secret

  tags = merge(var.tags, { Name = "/ecs/${var.environment}-${local.app_name}/COGNITO_CLIENT_SECRET" })
}
