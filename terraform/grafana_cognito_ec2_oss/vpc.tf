# -----------------------------------------------------------------------------
# Security Groups (VPC-scoped networking)
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb_oss" {
  name        = "${local.aws_name_prefix}-alb"
  description = "ALB for ${local.app_name} (OSS sample)"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = local.alb_ingress_cidrs
    description = "HTTP from allowed CIDRs"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.alb_ingress_cidrs
    description = "HTTPS from allowed CIDRs"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.aws_name_prefix}-alb" })
}

resource "aws_security_group" "instance_oss" {
  name        = "${local.aws_name_prefix}-instance"
  description = "EC2 instance (Grafana)"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.grafana_port
    to_port         = var.grafana_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_oss.id]
    description     = "Grafana from ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.aws_name_prefix}-instance" })
}
