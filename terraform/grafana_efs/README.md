# grafana_efs

Terraform stack that runs **Grafana on ECS** behind an **Application Load Balancer** with **persistent storage** on EFS.

## What it does

- **ECS**: One task definition (single Grafana container, 512 CPU / 1024 MiB). Service runs in your existing EC2-type ECS cluster, in private subnets. Container runs as non-root (UID 472). ECS Exec enabled for debugging when the cluster supports it.
- **ALB**: Public HTTP listener on port 80; forwards to the Grafana task. Health checks use Grafana’s `/api/health` (HTTP 200). For production, consider adding HTTPS (e.g. ACM cert on 443).
- **EFS**: Grafana’s data lives on EFS at `/grafana-data` (mounted from the EFS access point). SQLite DB, dashboards, plugins, logs, and provisioning dirs all persist across task replacement. Access point uses POSIX user 472:472 and permissions 0755 (no root, no world-writable).
- **Secrets**: Optional admin password in SSM Parameter Store (SecureString), injected at runtime. Leave unset for default admin/admin.
- **Logs**: Container logs go to CloudWatch (`/ecs/{environment}-grafana`).
- **Network**: ALB ingress from deployer IP or `alb_ingress_cidrs`; tasks accept traffic only from the ALB; EFS accepts NFS only from the task security group.

**SQLite on EFS:** Single ECS task, one writer. For multiple instances or stronger durability, use an external DB (e.g. RDS).

**Persistence:** Dashboards and config are stored in the Grafana DB on EFS. Creating a dashboard and then restarting the service (or forcing a new deployment) keeps the dashboard.

## Prerequisites

- ECS cluster (EC2 launch type).
- VPC with at least two **private** subnets (for tasks and EFS mount targets) and two **public** subnets (for the ALB).

## Apply

```bash
cp terraform.tfvars.example terraform.tfvars
# Set: ecs_cluster_arn, vpc_id, private_subnet_ids, public_subnet_ids

terraform init
terraform apply
```

## After apply

- **URL**: Use the `web_url` output. Default login is **admin** / **admin** unless you set `grafana_admin_password` in tfvars.
- **Logs**: `log_group_grafana` output gives the CloudWatch log group name.
- **EFS**: `efs_id` is the file system ID; use it for backup/restore of the Grafana data path if needed.
