# -----------------------------------------------------------------------------
# Security Groups (VPC-scoped networking) — same pattern as grafana_base
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.environment}-${local.app_name}-alb"
  description = "ALB for ${local.app_name}"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = local.alb_ingress_cidrs
    description = "HTTP from allowed CIDRs"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-alb" })
}

resource "aws_security_group" "grafana_tasks" {
  name        = "${var.environment}-${local.app_name}-grafana-tasks"
  description = "ECS Grafana tasks from ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.grafana_port
    to_port         = var.grafana_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Grafana from ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-grafana-tasks" })
}

resource "aws_security_group" "loki_tasks" {
  name        = "${var.environment}-${local.app_name}-loki-tasks"
  description = "ECS Loki tasks; accepts push from WAF worker"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3100
    to_port         = 3100
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana_tasks.id]
    description     = "Loki query from Grafana"
  }

  ingress {
    from_port       = 3100
    to_port         = 3100
    protocol        = "tcp"
    security_groups = [aws_security_group.waf_worker.id]
    description     = "Loki push from WAF worker"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-loki-tasks" })
}

# WAF worker: egress-only (SQS, S3, Loki :3100).
resource "aws_security_group" "waf_worker" {
  name        = "${var.environment}-${local.app_name}-waf-worker"
  description = "WAF worker task ENIs (egress only)"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-waf-worker" })
}
