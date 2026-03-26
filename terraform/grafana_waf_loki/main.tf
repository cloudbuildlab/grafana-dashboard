# -----------------------------------------------------------------------------
# Data sources
# -----------------------------------------------------------------------------
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "http" "my_public_ip" {
  url = "https://checkip.amazonaws.com/"
}

# Existing WAF log bucket — not managed here; this stack adds the S3 event notification only.
data "aws_s3_bucket" "waf_logs" {
  bucket = var.waf_logs_bucket_name
}

# Bootstrap bucket change → ECS rollout Lambda (Python, no extra deps).
data "archive_file" "bootstrap_roll_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/bootstrap_roll/handler.py"
  output_path = "${path.module}/.build/bootstrap_roll.zip"
}
