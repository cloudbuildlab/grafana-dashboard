# -----------------------------------------------------------------------------
# WAF ingest Lambda (classic Lambda, VPC-attached)
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "waf" {
  function_name    = "${var.environment}-${local.app_name}-waf"
  description      = "Reads WAF log objects from SQS/S3 and pushes entries to Loki"
  role             = aws_iam_role.waf_lambda.arn
  runtime          = "nodejs24.x"
  handler          = "index.handler"
  filename        = data.archive_file.waf_zip.output_path
  source_code_hash = data.archive_file.waf_zip.output_base64sha256

  memory_size = 512
  timeout     = 60

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.waf_lambda.id]
  }

  environment {
    variables = {
      LOKI_URL = local.loki_push_url
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.waf_lambda_basic,
    aws_iam_role_policy_attachment.waf_lambda_vpc,
    aws_cloudwatch_log_group.waf_lambda,
  ]

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-waf" })
}

resource "aws_lambda_event_source_mapping" "waf_sqs" {
  event_source_arn        = aws_sqs_queue.waf_ingest.arn
  function_name           = aws_lambda_function.waf.arn
  batch_size              = 10
  enabled                 = true
  function_response_types = ["ReportBatchItemFailures"]
}
