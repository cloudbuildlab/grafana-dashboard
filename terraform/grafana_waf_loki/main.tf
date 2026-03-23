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

# Deployment artifact for the WAF ingest Lambda.
data "archive_file" "waf_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/.build/waf.zip"
  excludes    = ["node_modules/**"]
}
