# -----------------------------------------------------------------------------
# Local values (same app_name pattern as grafana_base / grafana_efs)
# -----------------------------------------------------------------------------
locals {
  app_name   = "grafana"
  stack_name = "${var.environment}-${local.app_name}"

  # Rolling (200% max) needs two tasks worth of RAM/CPU on the same instance briefly; single-node clusters often cannot place the second task and the deploy never finishes.
  ecs_deployment_min_healthy = var.ecs_stop_first_deployment ? 0 : var.ecs_deployment_minimum_healthy_percent
  ecs_deployment_max_pct     = var.ecs_stop_first_deployment ? 100 : var.ecs_deployment_maximum_percent

  my_public_ip_cidr = "${trimspace(data.http.my_public_ip.response_body)}/32"
  alb_ingress_cidrs = length(var.alb_ingress_cidrs) > 0 ? var.alb_ingress_cidrs : [local.my_public_ip_cidr]

  cloud_map_namespace = "${local.stack_name}.local"
  loki_push_url       = "http://loki.${local.cloud_map_namespace}:3100/loki/api/v1/push"
  ecs_cluster_name    = split("/", var.ecs_cluster_arn)[1]

  grafana_environment = concat(
    var.grafana_admin_password != "" ? [] : [
      { name = "GF_SECURITY_ADMIN_PASSWORD", value = "admin" }
    ],
    [
      { name = "GF_LOG_LEVEL", value = var.grafana_log_level },
      { name = "GF_SERVER_ROUTER_LOGGING", value = var.grafana_router_logging ? "true" : "false" },
    ]
  )

  # Populates Grafana EFS provisioning dirs and Promtail Docker volume before containers start.
  bootstrap_shell_grafana = <<-EOT
set -e
aws s3 sync "s3://${aws_s3_bucket.bootstrap.id}/grafana/datasources/" "/grafana-data/provisioning/datasources/"
aws s3 cp "s3://${aws_s3_bucket.bootstrap.id}/grafana/dashboards/provider.yaml" "/grafana-data/provisioning/dashboards/provider.yaml"
aws s3 sync "s3://${aws_s3_bucket.bootstrap.id}/grafana/dashboards/" "/grafana-data/provisioning/dashboards/waf/" --exclude "provider.yaml" --delete
aws s3 cp "s3://${aws_s3_bucket.bootstrap.id}/promtail/config.yaml" "/p/config.yaml"
EOT

  # Fetch Loki config from bootstrap (limits_config is not reliably overridden by flags alone).
  # Then wipe WAL to recover from corrupt segments left by a prior OOM kill.
  bootstrap_shell_loki = <<-EOT
set -e
mkdir -p /loki/config /loki/rules/fake /loki/rules-temp
aws s3 cp "s3://${aws_s3_bucket.bootstrap.id}/loki/local-config.yaml" "/loki/config/local-config.yaml"
aws s3 cp "s3://${aws_s3_bucket.bootstrap.id}/loki/rules/fake/waf.yaml" "/loki/rules/fake/waf.yaml"
rm -rf /loki/wal
# ECS-managed EBS mounts are root-owned by default; Loki image runs as uid 10001.
chown -R 10001:10001 /loki
EOT

  container_bootstrap_grafana = {
    name       = "bootstrap-grafana"
    image      = "public.ecr.aws/aws-cli/aws-cli:latest"
    essential  = false
    entryPoint = ["sh", "-c"]
    command    = [local.bootstrap_shell_grafana]
    mountPoints = [
      { sourceVolume = "grafana-data", containerPath = "/grafana-data", readOnly = false },
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

  container_bootstrap_loki = {
    name       = "bootstrap-loki"
    image      = "public.ecr.aws/aws-cli/aws-cli:latest"
    essential  = false
    entryPoint = ["sh", "-c"]
    command    = [local.bootstrap_shell_loki]
    mountPoints = [
      { sourceVolume = "loki-data", containerPath = "/loki", readOnly = false },
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
    # Bootstrap wipes /loki/wal before Loki starts (see bootstrap_shell_loki) so Loki never hits
    # corrupt WAL segments left by a prior OOM kill. Loki must wait for bootstrap to COMPLETE.
    dependsOn = [{ containerName = "bootstrap-loki", condition = "COMPLETE" }]
    command = [
      "-config.file=/loki/config/local-config.yaml",
      "-log.level=${var.loki_log_level}",
      # Internal querier→frontend gRPC is capped at 4 MB by default; WAF log query results
      # exceed that when the dashboard requests thousands of lines. Raise to 32 MB.
      "-server.grpc-max-recv-msg-size-bytes=33554432",
      "-server.grpc-max-send-msg-size-bytes=33554432",
      # TopK metric queries use a count-min-sketch heap; default 10k caps cardinality there.
      "-querier.engine.max-count-min-sketch-heap-size=500000",
      # Heavy query_range responses exceed defaults (read/write 30s, querier backend 1m) → client EOF.
      "-server.http-read-timeout=10m",
      "-server.http-write-timeout=10m",
      "-server.http-idle-timeout=15m",
      "-querier.query-timeout=10m",
      # max_query_series / query_timeout also in /loki/config/local-config.yaml (S3 + bootstrap).
      # Default per-tenant ingestion rate is 4 MB/s. Lambda concurrency is capped at 5
      # (≈1 MB/s combined), but raise the Loki limit to 16 MB/s as a safety buffer
      # in case of replay/backlog bursts.
      "-distributor.ingestion-rate-limit-mb=16",
      "-distributor.ingestion-burst-size-mb=32",
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.loki.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
    # No container healthCheck: grafana/loki is distroless (no /bin/sh, curl). Grafana/Promtail use
    # dependsOn START (not HEALTHY): ECS rejects HEALTHY without a configured health check on Loki.
  }

  container_grafana = {
    name  = "grafana"
    image = var.grafana_image
    # UID:GID matches EFS access point POSIX user (472:472) so writes persist correctly.
    user      = "472:472"
    essential = true
    # Create provisioning subdirs on EFS at startup before exec'ing the default entrypoint.
    entryPoint = ["/bin/sh", "-c"]
    command = [
      "mkdir -p /grafana-data/provisioning/dashboards/waf /grafana-data/provisioning/datasources /grafana-data/provisioning/plugins /grafana-data/provisioning/alerting && exec /run.sh"
    ]
    portMappings = [{
      containerPort = var.grafana_port
      hostPort      = var.grafana_port
      protocol      = "tcp"
      appProtocol   = "http"
    }]
    mountPoints = [{ sourceVolume = "grafana-data", containerPath = "/grafana-data", readOnly = false }]
    dependsOn = [
      { containerName = "bootstrap-grafana", condition = "COMPLETE" },
    ]
    environment = concat(local.grafana_environment, [
      { name = "GF_PATHS_DATA", value = "/grafana-data" },
      { name = "GF_PATHS_PLUGINS", value = "/grafana-data/plugins" },
      { name = "GF_PATHS_LOGS", value = "/grafana-data/log" },
      { name = "GF_PATHS_PROVISIONING", value = "/grafana-data/provisioning" },
    ])
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
      { containerName = "bootstrap-grafana", condition = "COMPLETE" },
    ]
    command = ["-config.file=/etc/promtail/config.yaml", "-log.level=${var.promtail_log_level}"]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.promtail.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }

  # Sync container: run by the grafana_sync task definition on S3 ObjectCreated events.
  # Syncs dashboard JSON from S3 → EFS; Grafana's file poller picks up changes within 10s.
  container_sync_grafana = {
    name       = "sync-grafana"
    image      = "public.ecr.aws/aws-cli/aws-cli:latest"
    essential  = true
    entryPoint = ["sh", "-c"]
    command    = ["set -eux; aws s3 sync \"s3://${aws_s3_bucket.bootstrap.id}/grafana/datasources/\" \"/grafana-data/provisioning/datasources/\"; aws s3 cp \"s3://${aws_s3_bucket.bootstrap.id}/grafana/dashboards/provider.yaml\" \"/grafana-data/provisioning/dashboards/provider.yaml\"; aws s3 sync \"s3://${aws_s3_bucket.bootstrap.id}/grafana/dashboards/\" \"/grafana-data/provisioning/dashboards/waf/\" --exclude \"provider.yaml\" --delete; ls -la /grafana-data/provisioning/dashboards/waf/"]
    mountPoints = [
      { sourceVolume = "grafana-data", containerPath = "/grafana-data", readOnly = false },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.bootstrap.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "sync"
      }
    }
  }

  container_definitions_grafana = [
    local.container_bootstrap_grafana,
    local.container_grafana,
    local.container_promtail,
  ]

  container_definitions_loki = [
    local.container_bootstrap_loki,
    local.container_loki,
  ]

  container_definitions_sync_grafana = [
    local.container_sync_grafana,
  ]
}
