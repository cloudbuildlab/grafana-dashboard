# -----------------------------------------------------------------------------
# Application Load Balancer
# -----------------------------------------------------------------------------
resource "aws_lb" "app" {
  name               = "${var.environment}-${local.app_name}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  # Loki metric queries (topk/sum by high-cardinality label) can take >60s; raise to 600s
  # so the ALB does not 504 before Grafana streams the response back.
  idle_timeout = 600

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}" })
}

resource "aws_lb_target_group" "web" {
  name                 = "${var.environment}-${local.app_name}"
  port                 = var.grafana_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = var.alb_deregistration_delay_seconds

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/api/health"
    port                = "traffic-port"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = var.alb_healthcheck_interval_seconds
    timeout             = 5
  }

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}" })
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
