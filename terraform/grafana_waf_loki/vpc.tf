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

resource "aws_security_group" "tasks" {
  name        = "${var.environment}-${local.app_name}-tasks"
  description = "ECS tasks: Grafana from ALB; Loki HTTP push from WAF Lambda"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.grafana_port
    to_port         = var.grafana_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Grafana from ALB"
  }

  ingress {
    from_port       = 3100
    to_port         = 3100
    protocol        = "tcp"
    security_groups = [aws_security_group.waf_lambda.id]
    description     = "Loki push from WAF Lambda"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-tasks" })
}

# WAF Lambda: egress-only (SQS, S3, Loki :3100 on the task ENI).
resource "aws_security_group" "waf_lambda" {
  name        = "${var.environment}-${local.app_name}-waf-lambda"
  description = "WAF ingest Lambda ENIs (egress only)"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-waf-lambda" })
}
