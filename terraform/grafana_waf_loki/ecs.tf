# -----------------------------------------------------------------------------
# ECS Task Definition and Service (same cluster pattern as grafana_base)
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.environment}-${local.app_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "1024"
  memory                   = "1536"

  execution_role_arn    = aws_iam_role.ecs_execution.arn
  task_role_arn         = aws_iam_role.ecs_task.arn
  container_definitions = jsonencode(local.container_definitions)

  # Task-scoped Docker volumes (bootstrap init syncs S3 → grafana-prov / promtail-cfg).
  volume {
    name = "grafana-prov"
  }

  volume {
    name = "promtail-cfg"
  }

  # Loki persistence: path must exist on your ECS container instances (e.g. mounted EBS).
  volume {
    name      = "loki-data"
    host_path = "/mnt/loki"
  }

  # Host ECS agent logs for Promtail (standard path on ECS-optimized AMIs).
  volume {
    name      = "ecs-logs"
    host_path = "/var/log/ecs"
  }

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}" })

  depends_on = [
    aws_s3_bucket.bootstrap,
    aws_s3_object.datasource_loki,
    aws_s3_object.dashboard_provider,
    aws_s3_object.dashboard_waf,
    aws_s3_object.dashboard_waf_overview,
    aws_s3_object.dashboard_waf_geomap,
    aws_s3_object.promtail_config,
  ]
}

resource "aws_ecs_service" "app" {
  name            = "${var.environment}-${local.app_name}"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "EC2"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "grafana"
    container_port   = var.grafana_port
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.loki.arn
    container_name = "loki"
  }

  depends_on = [aws_lb_listener.app]

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}" })
}
