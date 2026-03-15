# grafana_base

Sample Terraform stack that runs **Grafana on ECS** behind an **Application Load Balancer**.

## What it does

- **ECS**: One task definition (single Grafana container, 512 CPU / 1024 MiB). Service runs in your existing EC2-type ECS cluster, in private subnets.
- **ALB**: Public HTTP listener on port 80; forwards to the Grafana task. Health checks use Grafana’s `/api/health` (HTTP 200).
- **Secrets**: Optional admin password can be set via variable; it is stored in **SSM Parameter Store** (SecureString) and injected into the task at runtime (no plain env in the task definition).
- **Logs**: Container logs go to a CloudWatch log group (`/ecs/{environment}-grafana`).
- **Network**: ALB allows HTTP from the deployer’s public IP only; tasks accept traffic only from the ALB security group.

No persistent storage: dashboards and config are in the container only and are lost when the task is replaced.

## Prerequisites

- ECS cluster (EC2 launch type).
- VPC with at least two **private** subnets (for tasks) and two **public** subnets (for the ALB).

## Apply

```bash
cp terraform.tfvars.example terraform.tfvars
# Set: ecs_cluster_arn, vpc_id, private_subnet_ids, public_subnet_ids

terraform init
terraform apply
```

## After apply

- **URL**: Use the `web_url` output (e.g. `http://<alb-dns-name>`). Default login is **admin** / **admin** unless you set `grafana_admin_password` in tfvars.
- **Logs**: `log_group_grafana` output gives the CloudWatch log group name.
