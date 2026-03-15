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
  description = "CIDR blocks allowed to reach the ALB on ports 80 and 443. If empty, deployer's public IP is used."
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ARN of the existing ACM certificate for HTTPS (must be in the same region as the ALB and valid for the Route 53 record name)."
  type        = string
}

variable "route53_zone_id" {
  description = "ID of the existing Route 53 hosted zone (e.g. Z1234...)."
  type        = string
}

variable "route53_record_name" {
  description = "DNS name for the Grafana record. Use subdomain (e.g. grafana) or FQDN (e.g. grafana.example.com) depending on the zone."
  type        = string
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

# -----------------------------------------------------------------------------
# Cognito users (optional)
# -----------------------------------------------------------------------------
variable "cognito_users" {
  description = "Map of group name to list of users to create. Each user: email (required), name (optional). Terraform creates each user and adds them to the group; Cognito sends a welcome email with a temporary password. Groups: grafana-admins, grafana-editors, grafana-viewers."
  type = map(list(object({
    email = string
    name  = optional(string, "")
  })))
  default = {}
}
