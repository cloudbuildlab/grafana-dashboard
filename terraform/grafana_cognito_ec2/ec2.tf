# -----------------------------------------------------------------------------
# EC2 instance running Grafana in Docker (same config as ECS stack)
# -----------------------------------------------------------------------------
resource "aws_instance" "grafana" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile    = aws_iam_instance_profile.grafana.name
  user_data_base64        = local.user_data

  # Allow Terraform to replace instance when user_data or AMI changes
  user_data_replace_on_change = true

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}" })

  depends_on = [aws_lb_listener.https]
}

resource "aws_lb_target_group_attachment" "grafana" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.grafana.id
  port             = var.grafana_port
}
