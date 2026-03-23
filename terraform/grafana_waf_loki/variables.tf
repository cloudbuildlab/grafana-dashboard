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
  description = "List of private subnet IDs for ECS tasks and Lambda ENIs."
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

# -----------------------------------------------------------------------------
# Loki / Promtail (optional pins)
# -----------------------------------------------------------------------------
variable "loki_image" {
  description = "Loki container image."
  type        = string
  default     = "grafana/loki:latest"
}

variable "promtail_image" {
  description = "Promtail container image."
  type        = string
  default     = "grafana/promtail:latest"
}
