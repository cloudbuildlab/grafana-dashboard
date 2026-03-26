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
  description = "Loki push URL used by the WAF worker (VPC-internal DNS)."
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

output "waf_worker_service_name" {
  description = "WAF ingest worker ECS service name."
  value       = aws_ecs_service.waf_worker.name
}

output "loki_service_name" {
  description = "Loki ECS service name."
  value       = aws_ecs_service.loki.name
}

output "bootstrap_roll_lambda_function_name" {
  description = "Lambda that forces ECS rollout on bootstrap S3 changes (null if disabled)."
  value       = var.enable_bootstrap_roll_lambda ? aws_lambda_function.bootstrap_roll[0].function_name : null
}

output "dashboard_sync_lambda_function_name" {
  description = "Lambda that triggers the ECS sync task when dashboard S3 objects change."
  value       = aws_lambda_function.dashboard_sync.function_name
}

output "efs_id" {
  description = "EFS file system ID for Grafana persistent data."
  value       = aws_efs_file_system.grafana.id
}

output "efs_access_point_id" {
  description = "EFS access point ID (POSIX 472:472) used by Grafana and sync tasks."
  value       = aws_efs_access_point.grafana.id
}
