# -----------------------------------------------------------------------------
# SQS — WAF ingest queue + DLQ
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "waf_ingest_dlq" {
  name                      = "${local.stack_name}-waf-ingest-dlq"
  message_retention_seconds = 1209600 # 14 days
  receive_wait_time_seconds = 20

  tags = merge(var.tags, { Name = "${local.stack_name}-waf-ingest-dlq" })
}

resource "aws_sqs_queue" "waf_ingest" {
  name = "${local.stack_name}-waf-ingest"

  # Worker polls continuously and ACKs only on successful push.
  visibility_timeout_seconds = 300
  receive_wait_time_seconds  = 20
  message_retention_seconds  = 86400 # 1 day; short because Lambda consumes quickly

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.waf_ingest_dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(var.tags, { Name = "${local.stack_name}-waf-ingest" })
}

# Allow S3 to publish events to the queue.
resource "aws_sqs_queue_policy" "waf_ingest" {
  queue_url = aws_sqs_queue.waf_ingest.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowS3SendMessage"
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.waf_ingest.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = data.aws_s3_bucket.waf_logs.arn }
      }
    }]
  })
}

# S3 event notification → SQS (replaces the former S3 → Lambda direct trigger).
resource "aws_s3_bucket_notification" "waf_logs" {
  bucket = data.aws_s3_bucket.waf_logs.id

  queue {
    queue_arn     = aws_sqs_queue.waf_ingest.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = var.waf_logs_prefix != "" ? var.waf_logs_prefix : null
    filter_suffix = var.waf_logs_object_suffix != "" ? var.waf_logs_object_suffix : null
  }

  depends_on = [aws_sqs_queue_policy.waf_ingest]
}
