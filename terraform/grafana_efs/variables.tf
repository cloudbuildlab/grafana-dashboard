# -----------------------------------------------------------------------------
# Input variables
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
  description = "List of private subnet IDs for ECS tasks."
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
  description = "Container image for Grafana. Pin to a specific tag for reproducibility and security (e.g. grafana/grafana:10.4.0)."
  type        = string
  default     = "grafana/grafana:10.4.0"
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
