# -----------------------------------------------------------------------------
# Outputs (web_url + log group mirror grafana_base)
# -----------------------------------------------------------------------------
output "web_url" {
  description = "URL to Grafana (via ALB)."
  value       = "http://${aws_lb.app.dns_name}"
}

output "log_group_grafana" {
  description = "CloudWatch log group name for the Grafana container."
  value       = aws_cloudwatch_log_group.grafana.name
}

output "loki_push_url" {
  description = "Loki push URL used by the WAF Lambda (VPC-internal DNS)."
  value       = local.loki_push_url
}

output "sqs_waf_queue_url" {
  description = "SQS queue URL for S3 → WAF log notifications."
  value       = aws_sqs_queue.waf_ingest.url
}

output "sqs_dlq_url" {
  description = "SQS dead-letter queue URL."
  value       = aws_sqs_queue.waf_ingest_dlq.url
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN passed into this stack (passthrough)."
  value       = var.ecs_cluster_arn
}

output "bootstrap_bucket" {
  description = "S3 bucket with Grafana provisioning objects and Promtail config."
  value       = aws_s3_bucket.bootstrap.id
}

output "cloudmap_namespace" {
  description = "Cloud Map private DNS namespace; loki.<namespace> resolves to the task ENI."
  value       = local.cloud_map_namespace
}

output "waf_lambda_name" {
  description = "WAF ingest Lambda function name."
  value       = aws_lambda_function.waf.function_name
}
