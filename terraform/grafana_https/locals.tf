# -----------------------------------------------------------------------------
# Local values
# -----------------------------------------------------------------------------
locals {
  my_public_ip_cidr = "${trimspace(data.http.my_public_ip.response_body)}/32"
  app_name          = "grafana"
  alb_ingress_cidrs = length(var.alb_ingress_cidrs) > 0 ? var.alb_ingress_cidrs : [local.my_public_ip_cidr]

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
    environment = [
      { name = "GF_PATHS_DATA", value = "/grafana-data" },
      { name = "GF_PATHS_PLUGINS", value = "/grafana-data/plugins" },
      { name = "GF_PATHS_LOGS", value = "/grafana-data/log" },
      { name = "GF_PATHS_PROVISIONING", value = "/grafana-data/provisioning" }
    ]
    secrets = var.grafana_admin_password != "" ? [
      { name = "GF_SECURITY_ADMIN_PASSWORD", valueFrom = aws_ssm_parameter.grafana_admin_password[0].arn }
    ] : []
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
