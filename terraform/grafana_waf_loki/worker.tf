# -----------------------------------------------------------------------------
# ECS worker service — consumes S3->SQS notifications and pushes to Loki
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "waf_worker" {
  name              = "/ecs/${var.environment}-${local.app_name}-waf-worker"
  retention_in_days = 7
  skip_destroy      = false

  tags = merge(var.tags, { Name = "/ecs/${var.environment}-${local.app_name}-waf-worker" })
}

resource "aws_ecs_task_definition" "waf_worker" {
  family                   = "${var.environment}-${local.app_name}-waf-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "512"
  memory                   = "1024"

  execution_role_arn = aws_iam_role.waf_worker_execution.arn
  task_role_arn      = aws_iam_role.waf_worker_task.arn

  container_definitions = jsonencode([
    {
      name      = "waf-worker"
      image     = "${var.waf_worker_image}:${var.waf_worker_image_tag}"
      essential = true
      environment = [
        { name = "AWS_REGION", value = data.aws_region.current.region },
        { name = "SQS_QUEUE_URL", value = aws_sqs_queue.waf_ingest.url },
        { name = "LOKI_URL", value = local.loki_push_url },
        { name = "HEALTH_LISTEN_ADDR", value = "0.0.0.0:8080" },
        { name = "WORKER_CONCURRENCY", value = "2" },
        { name = "POLL_WAIT_SECONDS", value = "20" },
        { name = "POLL_MAX_MESSAGES", value = "10" },
        { name = "WAF_ACL_ALLOWLIST", value = "" },
        { name = "WAF_ACTION_ALLOWLIST", value = "" },
      ]
      portMappings = [{ containerPort = 8080, protocol = "tcp" }]
      healthCheck = {
        command     = ["CMD", var.waf_worker_health_binary_path, "probe"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 90
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.waf_worker.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-waf-worker" })
}

resource "aws_ecs_service" "waf_worker" {
  name            = "${var.environment}-${local.app_name}-waf-worker"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.waf_worker.arn
  desired_count   = var.waf_worker_min_capacity
  launch_type     = "EC2"

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 50

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.waf_worker.id]
    assign_public_ip = false
  }

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-waf-worker" })
}

resource "aws_appautoscaling_target" "waf_worker" {
  max_capacity       = var.waf_worker_max_capacity
  min_capacity       = var.waf_worker_min_capacity
  resource_id        = "service/${local.ecs_cluster_name}/${aws_ecs_service.waf_worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "waf_worker_scale_up" {
  name               = "${var.environment}-${local.app_name}-waf-worker-scale-up"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.waf_worker.resource_id
  scalable_dimension = aws_appautoscaling_target.waf_worker.scalable_dimension
  service_namespace  = aws_appautoscaling_target.waf_worker.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

resource "aws_appautoscaling_policy" "waf_worker_scale_down" {
  name               = "${var.environment}-${local.app_name}-waf-worker-scale-down"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.waf_worker.resource_id
  scalable_dimension = aws_appautoscaling_target.waf_worker.scalable_dimension
  service_namespace  = aws_appautoscaling_target.waf_worker.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 120
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "waf_worker_scale_up" {
  alarm_name          = "${var.environment}-${local.app_name}-waf-worker-queue-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = var.waf_worker_scale_messages_per_task
  alarm_description   = "Scale up worker service when queue grows"
  dimensions = {
    QueueName = aws_sqs_queue.waf_ingest.name
  }
  alarm_actions = [aws_appautoscaling_policy.waf_worker_scale_up.arn]
}

resource "aws_cloudwatch_metric_alarm" "waf_worker_scale_down" {
  alarm_name          = "${var.environment}-${local.app_name}-waf-worker-queue-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 4
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Scale down worker service when queue is nearly empty"
  dimensions = {
    QueueName = aws_sqs_queue.waf_ingest.name
  }
  alarm_actions = [aws_appautoscaling_policy.waf_worker_scale_down.arn]
}
