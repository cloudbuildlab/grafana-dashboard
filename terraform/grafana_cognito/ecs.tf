# -----------------------------------------------------------------------------
# ECS Task Definition and Service
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.environment}-${local.app_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "512"
  memory                   = "1024"

  execution_role_arn    = aws_iam_role.ecs_execution.arn
  task_role_arn         = aws_iam_role.ecs_task.arn
  container_definitions = jsonencode(local.container_definitions)

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

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}" })
}

resource "aws_ecs_service" "app" {
  name            = "${var.environment}-${local.app_name}"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "EC2"

  enable_execute_command = true

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

  depends_on = [aws_lb_listener.https]

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}" })
}
