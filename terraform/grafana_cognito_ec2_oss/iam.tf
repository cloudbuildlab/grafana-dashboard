# -----------------------------------------------------------------------------
# IAM Instance Profile for EC2 (SSM only)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "grafana_instance_oss" {
  name = "${local.aws_name_prefix}-ec2"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = merge(var.tags, { Name = "${local.aws_name_prefix}-ec2" })
}

resource "aws_iam_instance_profile" "grafana_oss" {
  name = "${local.aws_name_prefix}-ec2"
  role = aws_iam_role.grafana_instance_oss.name
}

# SSM Session Manager: register with SSM and accept Session Manager connections
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_oss" {
  role       = aws_iam_role.grafana_instance_oss.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# SSM GetParameter for Cognito client secret (required)
data "aws_iam_policy_document" "instance_ssm_cognito_oss" {
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [aws_ssm_parameter.cognito_client_secret_oss.arn]
  }
}

resource "aws_iam_role_policy" "instance_ssm_cognito_oss" {
  name   = "${local.aws_name_prefix}-ssm-cognito"
  role   = aws_iam_role.grafana_instance_oss.id
  policy = data.aws_iam_policy_document.instance_ssm_cognito_oss.json
}

# SSM GetParameter for admin password (optional)
data "aws_iam_policy_document" "instance_ssm_admin_oss" {
  count = var.grafana_admin_password != "" ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [aws_ssm_parameter.grafana_admin_password_oss[0].arn]
  }
}

resource "aws_iam_role_policy" "instance_ssm_admin_oss" {
  count  = var.grafana_admin_password != "" ? 1 : 0
  name   = "${local.aws_name_prefix}-ssm-admin"
  role   = aws_iam_role.grafana_instance_oss.id
  policy = data.aws_iam_policy_document.instance_ssm_admin_oss[0].json
}
