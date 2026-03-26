# -----------------------------------------------------------------------------
# Input variables (same networking / ECS inputs as grafana_base)
# -----------------------------------------------------------------------------
variable "ecs_cluster_arn" {
  description = "ARN of the existing ECS cluster (EC2 launch type)."
  type        = string
}

variable "vpc_id" {
  description = "ID of the existing VPC."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS task ENIs."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB."
  type        = list(string)
}

variable "alb_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the ALB on port 80. If empty, deployer's public IP is used."
  type        = list(string)
  default     = []
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "ecs_task_cpu" {
  description = "Task CPU units for the Loki task (1024 = 1 vCPU). Raise if Loki is CPU-throttled under heavy ingestion."
  type        = number
  default     = 2048
}

variable "ecs_task_memory_mib" {
  description = "Task memory hard limit in MiB for the Loki task. Keep above 2 GiB to avoid OOM kills (exit 137) under normal WAF log ingestion."
  type        = number
  default     = 3072
}

variable "grafana_task_cpu" {
  description = "Task CPU units for the Grafana task (Grafana + Promtail). 256 is enough for a low-traffic dashboard; raise to 512 if Grafana is slow to render."
  type        = number
  default     = 256
}

variable "grafana_task_memory_mib" {
  description = "Task memory hard limit in MiB for the Grafana task (Grafana + Promtail). 512 MiB is sufficient for a single-user dashboard."
  type        = number
  default     = 512
}

variable "ecs_deployment_minimum_healthy_percent" {
  description = <<-EOT
    Minimum healthy task count during a deployment, as percent of desired_count.
    With 100 and ecs_deployment_maximum_percent 200, ECS starts the new task before stopping the old one (rolling replace behind the ALB).
    Requires enough CPU/memory on the cluster to place two tasks briefly; otherwise ECS may stop the old task first (downtime).
  EOT
  type        = number
  default     = 100
}

variable "ecs_deployment_maximum_percent" {
  description = "Upper bound on task count during deployment, as percent of desired_count. 200 allows one extra task when desired_count is 1."
  type        = number
  default     = 200
}

variable "ecs_stop_first_deployment" {
  description = <<-EOT
    When true (recommended for a single EC2 instance or tight RAM), deployments use minimum healthy 0% and maximum 100%:
    ECS stops the old task before starting the new one, so you never need 2× task memory/CPU on one host.
    ECS Availability Zone rebalancing is turned off in that mode (AWS does not allow maxPercent <= 100 with rebalancing on).
    When false, uses ecs_deployment_*_percent below for rolling (zero-downtime if the cluster can run two tasks); AZ rebalancing stays enabled.
  EOT
  type        = bool
  default     = true
}

variable "ecs_deployment_circuit_breaker_rollback" {
  description = "When true, failed deployments roll back to the last steady task definition. Set false temporarily to debug a stuck deploy (task will stay on broken revision until fixed)."
  type        = bool
  default     = true
}

variable "ecs_health_check_grace_period_seconds" {
  description = "After a task starts, ALB health check failures are ignored for this long. Covers bootstrap + Loki + Grafana so the new task is not marked unhealthy before it serves /api/health."
  type        = number
  default     = 300
}

variable "alb_deregistration_delay_seconds" {
  description = "ALB target deregistration drain timeout in seconds. Lower values speed stop-first task replacements; 30s is usually enough for Grafana HTTP requests."
  type        = number
  default     = 30
}

variable "alb_healthcheck_interval_seconds" {
  description = "ALB target group health check interval in seconds."
  type        = number
  default     = 15
}

variable "enable_bootstrap_roll_lambda" {
  description = "When true, bootstrap S3 object creates/updates invoke a Lambda that forces a new ECS deployment so the bootstrap container re-syncs provisioning."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "grafana_image" {
  description = "Container image for Grafana."
  type        = string
  default     = "grafana/grafana:latest"
}

variable "grafana_port" {
  description = "Port Grafana listens on."
  type        = number
  default     = 3000
}

variable "grafana_admin_password" {
  description = "Optional: Grafana admin password. Stored in SSM Parameter Store (SecureString) and injected into the task as GF_SECURITY_ADMIN_PASSWORD. Leave empty for default admin/admin."
  type        = string
  default     = ""
  sensitive   = true
}

# -----------------------------------------------------------------------------
# WAF ingest
# -----------------------------------------------------------------------------
variable "waf_logs_bucket_name" {
  description = <<-EOT
    Name of an existing S3 bucket containing WAF log objects. This stack does not create the bucket.
    For WAFv2 direct log delivery to S3, the bucket name must start with aws-waf-logs-.
  EOT
  type        = string
}

variable "waf_logs_prefix" {
  description = "Optional S3 key prefix filter for the WAF log trigger (e.g. \"AWSLogs/\"). Empty means all keys."
  type        = string
  default     = ""
}

variable "waf_logs_object_suffix" {
  description = "S3 notification suffix filter (e.g. \".gz\" for WAFv2 delivery). Empty omits the filter."
  type        = string
  default     = ".gz"
}

variable "web_acl_arn" {
  description = "ARN of an existing WAFv2 Web ACL. When set, enables WAF log delivery to the waf_logs bucket."
  type        = string
  default     = ""
}

variable "waf_worker_image" {
  description = "Container image repository for the WAF worker (for example account.dkr.ecr.region.amazonaws.com/waf-log-worker-image)."
  type        = string
}

variable "waf_worker_image_tag" {
  description = "Container image tag for the WAF worker."
  type        = string
  default     = "latest"
}

variable "waf_worker_min_capacity" {
  description = "Minimum number of WAF worker ECS tasks."
  type        = number
  default     = 1
}

variable "waf_worker_max_capacity" {
  description = "Maximum number of WAF worker ECS tasks."
  type        = number
  default     = 5
}

variable "waf_worker_scale_messages_per_task" {
  description = "Target SQS visible message count per worker task for autoscaling."
  type        = number
  default     = 100
}

# -----------------------------------------------------------------------------
# Loki / Promtail (optional pins)
# -----------------------------------------------------------------------------
variable "loki_image" {
  description = "Loki container image."
  type        = string
  default     = "grafana/loki:latest"
}

variable "loki_ebs_size_gb" {
  description = "Size in GiB for the ECS-managed EBS volume attached to each Loki task."
  type        = number
  default     = 20
}

variable "loki_ebs_volume_type" {
  description = "EBS volume type for Loki task storage (for example gp3 or io2)."
  type        = string
  default     = "gp3"
}

variable "promtail_image" {
  description = "Promtail container image."
  type        = string
  default     = "grafana/promtail:latest"
}

variable "grafana_log_level" {
  description = "Grafana root log level (debug, info, warn, error). warn/error cut CloudWatch noise vs default info."
  type        = string
  default     = "warn"
}

variable "grafana_router_logging" {
  description = "When false, Grafana omits per-request HTTP router logs (major source of chatter on busy instances)."
  type        = bool
  default     = false
}

variable "loki_log_level" {
  description = "Loki -log.level (debug, info, warn, error). Matches grafana/loki single-binary images using /etc/loki/local-config.yaml."
  type        = string
  default     = "warn"
}

variable "promtail_log_level" {
  description = "Promtail -log.level (debug, info, warn, error)."
  type        = string
  default     = "warn"
}
