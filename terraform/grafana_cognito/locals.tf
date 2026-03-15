# -----------------------------------------------------------------------------
# Local values
# -----------------------------------------------------------------------------
locals {
  my_public_ip_cidr = "${trimspace(data.http.my_public_ip.response_body)}/32"
  app_name          = "grafana"
  alb_ingress_cidrs = length(var.alb_ingress_cidrs) > 0 ? var.alb_ingress_cidrs : [local.my_public_ip_cidr]

  # Flatten cognito_users: list of { email, name, group } for aws_cognito_user and outputs
  flat_cognito_users = length(var.cognito_users) > 0 ? flatten([
    for group_name, users in var.cognito_users : [
      for u in users : merge(u, { group = group_name })
    ]
  ]) : []

  grafana_fqdn       = trimsuffix(aws_route53_record.grafana.fqdn, ".")
  cognito_domain_url = "https://${aws_cognito_user_pool_domain.grafana.domain}.auth.${data.aws_region.current.id}.amazoncognito.com"

  grafana_container = {
    name      = "grafana"
    image     = var.grafana_image
    essential = true
    # Explicit UID:GID to match EFS access point so writes persist (stops "starting from scratch").
    user = "472:472"
    # Create provisioning subdirs on EFS at startup so Grafana does not log errors.
    entryPoint = ["/bin/sh", "-c"]
    command = [
      <<-EOT
        mkdir -p /grafana-data/provisioning/dashboards \
                 /grafana-data/provisioning/datasources \
                 /grafana-data/provisioning/plugins \
                 /grafana-data/provisioning/alerting && exec /run.sh
      EOT
    ]
    portMappings = [{
      containerPort = var.grafana_port
      hostPort      = var.grafana_port
      protocol      = "tcp"
      appProtocol   = "http"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.grafana.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
    # All writable paths on EFS so dashboard service state and DB persist.
    environment = concat(
      [
        { name = "GF_PATHS_DATA", value = "/grafana-data" },
        { name = "GF_PATHS_PLUGINS", value = "/grafana-data/plugins" },
        { name = "GF_PATHS_LOGS", value = "/grafana-data/log" },
        { name = "GF_PATHS_PROVISIONING", value = "/grafana-data/provisioning" },
        { name = "GF_SERVER_ROOT_URL", value = "https://${local.grafana_fqdn}" },
        { name = "GF_AUTH_GENERIC_OAUTH_ENABLED", value = "true" },
        { name = "GF_AUTH_GENERIC_OAUTH_NAME", value = "Cognito" },
        { name = "GF_AUTH_GENERIC_OAUTH_CLIENT_ID", value = aws_cognito_user_pool_client.grafana.id },
        { name = "GF_AUTH_GENERIC_OAUTH_SCOPES", value = "openid profile email" },
        { name = "GF_AUTH_GENERIC_OAUTH_AUTH_URL", value = "${local.cognito_domain_url}/oauth2/authorize" },
        { name = "GF_AUTH_GENERIC_OAUTH_TOKEN_URL", value = "${local.cognito_domain_url}/oauth2/token" },
        { name = "GF_AUTH_GENERIC_OAUTH_API_URL", value = "${local.cognito_domain_url}/oauth2/userInfo" },
        { name = "GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP", value = "true" },
        { name = "GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH", value = "grafana_role" },
        { name = "GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_STRICT", value = "true" },
        { name = "GF_AUTH_GENERIC_OAUTH_ALLOW_ASSIGN_GRAFANA_ADMIN", value = "true" },
        { name = "GF_AUTH_DISABLE_LOGIN_FORM", value = "false" }
      ]
    )
    secrets = concat(
      var.grafana_admin_password != "" ? [{ name = "GF_SECURITY_ADMIN_PASSWORD", valueFrom = aws_ssm_parameter.grafana_admin_password[0].arn }] : [],
      [{ name = "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET", valueFrom = aws_ssm_parameter.cognito_client_secret.arn }]
    )
    mountPoints = [{
      sourceVolume  = "grafana-data"
      containerPath = "/grafana-data"
      readOnly      = false
    }]
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f -s http://127.0.0.1:${var.grafana_port}/api/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 90
    }
  }

  container_definitions = [local.grafana_container]
}
