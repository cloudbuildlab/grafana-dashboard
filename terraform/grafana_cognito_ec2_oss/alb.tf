# -----------------------------------------------------------------------------
# Application Load Balancer (HTTPS on 443, HTTP 80 redirects to HTTPS) + Route 53
# -----------------------------------------------------------------------------
resource "aws_lb" "app_oss" {
  name               = local.aws_name_prefix
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_oss.id]
  subnets            = var.public_subnet_ids

  tags = merge(var.tags, { Name = local.aws_name_prefix })
}

resource "aws_lb_target_group" "web_oss" {
  name        = local.aws_name_prefix
  port        = var.grafana_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/api/health"
    port                = "traffic-port"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = merge(var.tags, { Name = local.aws_name_prefix })
}

resource "aws_lb_listener" "https_oss" {
  load_balancer_arn = aws_lb.app_oss.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_oss.arn
  }
}

# Default: forward HTTP so http://<elb-dns>/ works (ACM cert does not cover *.elb.amazonaws.com,
# so HTTPS to the ELB hostname would fail). Cognito / GF_SERVER_ROOT_URL still use the Route 53 name on HTTPS.
resource "aws_lb_listener" "http_oss" {
  load_balancer_arn = aws_lb.app_oss.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_oss.arn
  }
}

# If someone opens http://<your-grafana-hostname>/ , send them to HTTPS (valid cert on 443).
resource "aws_lb_listener_rule" "http_redirect_dns_to_https_oss" {
  listener_arn = aws_lb_listener.http_oss.arn
  priority     = 10

  action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    host_header {
      values = [trimsuffix(aws_route53_record.grafana_oss.fqdn, ".")]
    }
  }
}

resource "aws_route53_record" "grafana_oss" {
  zone_id = var.route53_zone_id
  name    = var.route53_record_name
  type    = "A"

  alias {
    name                   = aws_lb.app_oss.dns_name
    zone_id                = aws_lb.app_oss.zone_id
    evaluate_target_health = true
  }
}
