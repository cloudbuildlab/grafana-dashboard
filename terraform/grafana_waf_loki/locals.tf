# -----------------------------------------------------------------------------
# Local values (same app_name pattern as grafana_base / grafana_efs)
# -----------------------------------------------------------------------------
locals {
  app_name   = "grafana"
  stack_name = "${var.environment}-${local.app_name}"

  my_public_ip_cidr = "${trimspace(data.http.my_public_ip.response_body)}/32"
  alb_ingress_cidrs = length(var.alb_ingress_cidrs) > 0 ? var.alb_ingress_cidrs : [local.my_public_ip_cidr]

  cloud_map_namespace = "${local.stack_name}.local"
  loki_push_url       = "http://loki.${local.cloud_map_namespace}:3100/loki/api/v1/push"

  # Populates Docker task volumes from the bootstrap S3 bucket before other containers start.
  bootstrap_shell = <<-EOT
set -e
aws s3 sync "s3://${aws_s3_bucket.bootstrap.id}/grafana/datasources/" "/g/datasources/"
aws s3 sync "s3://${aws_s3_bucket.bootstrap.id}/grafana/dashboards/" "/g/dashboards/"
aws s3 cp "s3://${aws_s3_bucket.bootstrap.id}/promtail/config.yaml" "/p/config.yaml"
EOT

  container_bootstrap = {
    name       = "bootstrap"
    image      = "public.ecr.aws/aws-cli/aws-cli:latest"
    essential  = false
    entryPoint = ["sh", "-c"]
    command    = [local.bootstrap_shell]
    mountPoints = [
      { sourceVolume = "grafana-prov", containerPath = "/g", readOnly = false },
      { sourceVolume = "promtail-cfg", containerPath = "/p", readOnly = false },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.bootstrap.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }

  container_loki = {
    name      = "loki"
    image     = var.loki_image
    essential = true
    portMappings = [{
      containerPort = 3100
      hostPort      = 3100
      protocol      = "tcp"
    }]
    mountPoints = [{ sourceVolume = "loki-data", containerPath = "/loki", readOnly = false }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.loki.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "curl -fsS http://127.0.0.1:3100/ready || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }

  container_grafana = {
    name      = "grafana"
    image     = var.grafana_image
    essential = true
    portMappings = [{
      containerPort = var.grafana_port
      hostPort      = var.grafana_port
      protocol      = "tcp"
      appProtocol   = "http"
    }]
    mountPoints = [{ sourceVolume = "grafana-prov", containerPath = "/etc/grafana/provisioning", readOnly = true }]
    dependsOn = [
      { containerName = "bootstrap", condition = "COMPLETE" },
      { containerName = "loki", condition = "HEALTHY" },
    ]
    environment = var.grafana_admin_password != "" ? [] : [
      { name = "GF_SECURITY_ADMIN_PASSWORD", value = "admin" }
    ]
    secrets = var.grafana_admin_password != "" ? [
      { name = "GF_SECURITY_ADMIN_PASSWORD", valueFrom = aws_ssm_parameter.grafana_admin_password[0].arn }
    ] : []
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.grafana.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f -s http://127.0.0.1:${var.grafana_port}/api/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 90
    }
  }

  container_promtail = {
    name      = "promtail"
    image     = var.promtail_image
    essential = false
    mountPoints = [
      { sourceVolume = "ecs-logs", containerPath = "/var/log/ecs", readOnly = true },
      { sourceVolume = "promtail-cfg", containerPath = "/etc/promtail", readOnly = true },
    ]
    dependsOn = [
      { containerName = "bootstrap", condition = "COMPLETE" },
      { containerName = "loki", condition = "HEALTHY" },
    ]
    command = ["-config.file=/etc/promtail/config.yaml"]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.promtail.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }

  container_definitions = [
    local.container_bootstrap,
    local.container_loki,
    local.container_grafana,
    local.container_promtail,
  ]
}
