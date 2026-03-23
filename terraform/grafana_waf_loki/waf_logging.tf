# -----------------------------------------------------------------------------
# Optional: WAFv2 logging configuration
# -----------------------------------------------------------------------------
resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count = var.web_acl_arn != "" ? 1 : 0

  resource_arn            = var.web_acl_arn
  log_destination_configs = [data.aws_s3_bucket.waf_logs.arn]
}
