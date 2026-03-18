# grafana_cognito_ec2_oss

Sample variant of [grafana_cognito_ec2](../grafana_cognito_ec2/README.md). **AWS resource names use the prefix `{environment}-grafana-oss`** (ALB, target group, IAM roles, security groups, Cognito pool/domain, Lambda, SSM paths) so this stack can run in the same account/VPC alongside `grafana_cognito_ec2` without name clashes. Use a **different** `route53_record_name` (e.g. `grafana-oss`) so DNS does not overwrite the other stack’s record.

## What it does

- **EC2**: Amazon Linux 2; user data installs Docker, creates `/grafana-data`, fetches secrets from SSM, runs Grafana in Docker. Private subnet; access via SSM Session Manager only (no SSH key).
- **ALB**: HTTPS 443 (ACM, must match your Route 53 hostname). HTTP 80 forwards to Grafana so `http://<elb-dns>/` works (HTTPS to the ELB hostname would fail cert validation). Requests to your DNS name on port 80 redirect to HTTPS.
- **Route 53**: A record (alias to ALB) in your hosted zone.
- **Cognito**: User Pool + app client (secret in SSM); Pre Token Lambda maps groups to `grafana_role`; groups: `grafana-admins`, `grafana-editors`, `grafana-viewers`.
- **Secrets**: Cognito client secret and optional admin password in SSM (`/ec2/<env>-grafana-oss/...`), read at boot.

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
