# -----------------------------------------------------------------------------
# Cognito User Pool for Grafana SSO (OIDC) and RBAC via groups
# -----------------------------------------------------------------------------
resource "aws_cognito_user_pool" "grafana" {
  name = "${var.environment}-${local.app_name}"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  schema {
    name                = "preferred_username"
    attribute_data_type = "String"
    required            = false
    mutable             = true
  }

  deletion_protection = "INACTIVE"

  lambda_config {
    pre_token_generation = aws_lambda_function.cognito_pre_token.arn
  }

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}" })

  lifecycle {
    ignore_changes = [schema]
  }
}

resource "aws_cognito_user_pool_domain" "grafana" {
  domain       = "${var.environment}-${local.app_name}-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.grafana.id
}

resource "aws_cognito_user_pool_client" "grafana" {
  name         = "${var.environment}-${local.app_name}-oidc"
  user_pool_id = aws_cognito_user_pool.grafana.id

  generate_secret = true

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
  supported_identity_providers = ["COGNITO"]

  callback_urls = ["https://${trimsuffix(aws_route53_record.grafana.fqdn, ".")}/login/generic_oauth"]
  logout_urls   = ["https://${trimsuffix(aws_route53_record.grafana.fqdn, ".")}"]

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]

  read_attributes  = ["email", "preferred_username"]
  write_attributes = ["email", "preferred_username"]

  prevent_user_existence_errors = "ENABLED"
}

resource "aws_cognito_user_group" "grafana_admins" {
  name         = "grafana-admins"
  user_pool_id = aws_cognito_user_pool.grafana.id
  precedence   = 10
}

resource "aws_cognito_user_group" "grafana_editors" {
  name         = "grafana-editors"
  user_pool_id = aws_cognito_user_pool.grafana.id
  precedence   = 20
}

resource "aws_cognito_user_group" "grafana_viewers" {
  name         = "grafana-viewers"
  user_pool_id = aws_cognito_user_pool.grafana.id
  precedence   = 30
}
