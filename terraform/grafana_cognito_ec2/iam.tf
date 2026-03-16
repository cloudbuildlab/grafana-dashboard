# -----------------------------------------------------------------------------
# IAM Instance Profile for EC2 (SSM only)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "grafana_instance" {
  name = "${var.environment}-${local.app_name}-ec2"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-ec2" })
}

resource "aws_iam_instance_profile" "grafana" {
  name = "${var.environment}-${local.app_name}-ec2"
  role = aws_iam_role.grafana_instance.name
}

# SSM Session Manager: register with SSM and accept Session Manager connections
resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.grafana_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# SSM GetParameter for Cognito client secret (required)
data "aws_iam_policy_document" "instance_ssm_cognito" {
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [aws_ssm_parameter.cognito_client_secret.arn]
  }
}

resource "aws_iam_role_policy" "instance_ssm_cognito" {
  name   = "${var.environment}-${local.app_name}-ssm-cognito"
  role   = aws_iam_role.grafana_instance.id
  policy = data.aws_iam_policy_document.instance_ssm_cognito.json
}

# SSM GetParameter for admin password (optional)
data "aws_iam_policy_document" "instance_ssm_admin" {
  count = var.grafana_admin_password != "" ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [aws_ssm_parameter.grafana_admin_password[0].arn]
  }
}

resource "aws_iam_role_policy" "instance_ssm_admin" {
  count  = var.grafana_admin_password != "" ? 1 : 0
  name   = "${var.environment}-${local.app_name}-ssm-admin"
  role   = aws_iam_role.grafana_instance.id
  policy = data.aws_iam_policy_document.instance_ssm_admin[0].json
}
