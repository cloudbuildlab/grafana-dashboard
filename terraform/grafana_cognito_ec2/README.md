# grafana_cognito_ec2

Terraform stack: **Grafana on a single EC2 instance** behind an ALB with HTTPS (ACM), Route 53, and **Cognito SSO** with RBAC. Same behaviour as the ECS stack [grafana_cognito](../grafana_cognito/README.md), with EC2 as compute (no ECS). Data is on instance disk only (no EFS).

## What it does

- **EC2**: Amazon Linux 2; user data installs Docker, creates `/grafana-data`, fetches secrets from SSM, runs Grafana in Docker. Private subnet; access via SSM Session Manager only (no SSH key).
- **ALB**: HTTPS 443 (ACM), HTTP 80 → 443, health check `/api/health`, target type instance.
- **Route 53**: A record (alias to ALB) in your hosted zone.
- **Cognito**: User Pool + app client (secret in SSM); Pre Token Lambda maps groups to `grafana_role`; groups: `grafana-admins`, `grafana-editors`, `grafana-viewers`.
- **Secrets**: Cognito client secret and optional admin password in SSM (`/ec2/<env>-grafana/...`), read at boot.

## Prerequisites

- VPC with private subnets (EC2) and public subnets (ALB). Instance needs outbound internet (NAT or VPC endpoints) for Docker pull and SSM.
- ACM certificate (same region as ALB) covering the Grafana hostname.
- Route 53 hosted zone; stack creates only the A record.

## Apply

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit: vpc_id, private_subnet_ids, public_subnet_ids, acm_certificate_arn, route53_zone_id, route53_record_name

terraform init
terraform apply
```

## After apply

- **URL**: `web_url` output. Sign in with **Login with Cognito** (or admin if `grafana_admin_password` is set).
- **Cognito**: Create users in the pool and add to the grafana-* groups. Outputs: `cognito_user_pool_id`, `cognito_user_pool_domain`, `cognito_app_client_id`.
- **Debug**: `instance_id` for SSM — `aws ssm start-session --target <instance_id>`. Check `/var/log/user-data.log` if Grafana doesn't start.
