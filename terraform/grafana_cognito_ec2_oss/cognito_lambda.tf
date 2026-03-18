# -----------------------------------------------------------------------------
# Pre Token Generation Lambda: injects grafana_role (Admin/Editor/Viewer) into
# the ID token from Cognito group membership so Grafana can apply RBAC.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "cognito_pre_token_oss" {
  name = "${local.aws_name_prefix}-cognito-pre-token"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "cognito_pre_token_logs_oss" {
  role       = aws_iam_role.cognito_pre_token_oss.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "cognito_pre_token_oss" {
  type        = "zip"
  source_file = "${path.module}/lambda/cognito_pre_token.js"
  output_path = "${path.module}/lambda/cognito_pre_token.zip"
}

resource "aws_lambda_function" "cognito_pre_token_oss" {
  function_name    = "${local.aws_name_prefix}-cognito-pre-token"
  role             = aws_iam_role.cognito_pre_token_oss.arn
  runtime          = "nodejs20.x"
  handler          = "cognito_pre_token.handler"
  filename         = "${path.module}/lambda/cognito_pre_token.zip"
  source_code_hash = data.archive_file.cognito_pre_token_oss.output_base64sha256

  tags = merge(var.tags, { Name = "${local.aws_name_prefix}-cognito-pre-token" })
}

resource "aws_lambda_permission" "cognito_pre_token_oss" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cognito_pre_token_oss.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.grafana_oss.arn
}
