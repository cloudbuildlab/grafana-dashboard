# -----------------------------------------------------------------------------
# ECS Task Definition and Service (same cluster pattern as grafana_base)
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "grafana" {
  family                   = "${var.environment}-${local.app_name}-grafana"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = tostring(var.grafana_task_cpu)
  memory                   = tostring(var.grafana_task_memory_mib)

  execution_role_arn    = aws_iam_role.ecs_execution.arn
  task_role_arn         = aws_iam_role.ecs_task.arn
  container_definitions = jsonencode(local.container_definitions_grafana)

  # EFS volume: persistent Grafana data (DB, plugins, logs, file provisioning).
  # Bootstrap syncs S3 provisioning files into this volume before Grafana starts.
  volume {
    name = "grafana-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.grafana.id
      root_directory     = "/"
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.grafana.id
        iam             = "ENABLED"
      }
    }
  }

  # Task-scoped Docker volume for Promtail config (bootstrap syncs from S3).
  volume {
    name = "promtail-cfg"
  }

  # Host ECS agent logs for Promtail (standard path on ECS-optimized AMIs).
  volume {
    name      = "ecs-logs"
    host_path = "/var/log/ecs"
  }

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-grafana" })

  depends_on = [
    aws_s3_bucket.bootstrap,
    aws_s3_object.datasource_loki,
    aws_s3_object.dashboard_provider,
    aws_s3_object.dashboard_json,
    aws_s3_object.promtail_config,
  ]
}

# Dashboard sync task: triggered by S3 ObjectCreated events via Lambda (not a service).
# Syncs grafana/dashboards/ from S3 → EFS; Grafana's file poller picks up changes within 10s.
resource "aws_ecs_task_definition" "grafana_sync" {
  family                   = "${var.environment}-${local.app_name}-grafana-sync"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "256"
  memory                   = "256"

  execution_role_arn    = aws_iam_role.sync_task_execution.arn
  task_role_arn         = aws_iam_role.sync_task.arn
  container_definitions = jsonencode(local.container_definitions_sync_grafana)

  volume {
    name = "grafana-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.grafana.id
      root_directory     = "/"
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.grafana.id
        iam             = "ENABLED"
      }
    }
  }

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-grafana-sync" })
}

resource "aws_ecs_task_definition" "loki" {
  family                   = "${var.environment}-${local.app_name}-loki"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = tostring(var.ecs_task_cpu)
  memory                   = tostring(var.ecs_task_memory_mib)

  execution_role_arn    = aws_iam_role.ecs_execution.arn
  task_role_arn         = aws_iam_role.ecs_task.arn
  container_definitions = jsonencode(local.container_definitions_loki)

  # Loki persistence is provided at service deployment via ECS-managed EBS.
  volume {
    name                = "loki-data"
    configure_at_launch = true
  }

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-loki" })

  depends_on = [
    aws_s3_bucket.bootstrap,
    aws_s3_object.loki_local_config,
  ]
}

resource "aws_ecs_service" "grafana" {
  name            = "${var.environment}-${local.app_name}-grafana"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = var.desired_count
  launch_type     = "EC2"

  # AZ rebalancing requires deployment_maximum_percent > 100; stop-first uses 100% max.
  availability_zone_rebalancing = local.ecs_deployment_max_pct <= 100 ? "DISABLED" : "ENABLED"

  health_check_grace_period_seconds = var.ecs_health_check_grace_period_seconds

  deployment_maximum_percent         = local.ecs_deployment_max_pct
  deployment_minimum_healthy_percent = local.ecs_deployment_min_healthy

  deployment_circuit_breaker {
    enable   = var.ecs_deployment_circuit_breaker_rollback
    rollback = var.ecs_deployment_circuit_breaker_rollback
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.grafana_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "grafana"
    container_port   = var.grafana_port
  }

  # Deterministic rollout when provisioned S3 content changes (dashboards/datasources/promtail/alerting).
  # This avoids relying solely on S3->Lambda event timing for dashboard refresh.
  force_new_deployment = true
  triggers = {
    bootstrap_content = sha1(join(",", [
      aws_s3_object.datasource_loki.etag,
      aws_s3_object.datasource_loki_prom.etag,
      aws_s3_object.dashboard_provider.etag,
      aws_s3_object.promtail_config.etag,
      aws_s3_object.alerting_sqli.etag,
    ]))
  }

  depends_on = [
    aws_lb_listener.app,
    aws_s3_object.dashboard_json,
  ]

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-grafana" })
}

resource "aws_ecs_service" "loki" {
  name            = "${var.environment}-${local.app_name}-loki"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.loki.arn
  desired_count   = var.desired_count
  launch_type     = "EC2"

  # AZ rebalancing requires deployment_maximum_percent > 100; stop-first uses 100% max.
  availability_zone_rebalancing = local.ecs_deployment_max_pct <= 100 ? "DISABLED" : "ENABLED"

  deployment_maximum_percent         = local.ecs_deployment_max_pct
  deployment_minimum_healthy_percent = local.ecs_deployment_min_healthy

  deployment_circuit_breaker {
    enable   = var.ecs_deployment_circuit_breaker_rollback
    rollback = var.ecs_deployment_circuit_breaker_rollback
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.loki_tasks.id]
    assign_public_ip = false
  }

  # Private DNS A-record registry: do not set container_port (ECS API rejects it).
  service_registries {
    registry_arn   = aws_service_discovery_service.loki.arn
    container_name = "loki"
  }

  volume_configuration {
    name = "loki-data"
    managed_ebs_volume {
      role_arn         = aws_iam_role.ecs_ebs.arn
      size_in_gb       = var.loki_ebs_size_gb
      volume_type      = var.loki_ebs_volume_type
      file_system_type = "ext4"
    }
  }

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-loki" })
}
