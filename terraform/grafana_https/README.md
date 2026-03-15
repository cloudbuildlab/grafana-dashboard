# grafana_https

Terraform stack that runs **Grafana on ECS** behind an **Application Load Balancer** with **HTTPS** (ACM) and a **Route 53** record. Persistent storage on EFS.

## What it does

- **ECS**: One task definition (single Grafana container, 512 CPU / 1024 MiB). Service runs in your existing EC2-type ECS cluster, in private subnets. Container runs as non-root (UID 472). ECS Exec enabled for debugging when the cluster supports it.
- **ALB**: HTTPS listener on 443 (existing ACM cert); HTTP on 80 redirects to HTTPS. Health checks use Grafana’s `/api/health` (HTTP 200).
- **Route 53**: Creates an A alias record in an existing hosted zone pointing at the ALB. Set `route53_zone_id` and `route53_record_name`; the zone must already exist.
- **EFS**: Grafana’s data lives on EFS at `/grafana-data`. SQLite DB, dashboards, plugins, logs, and provisioning dirs persist across task replacement.
- **Secrets**: Optional admin password in SSM Parameter Store (SecureString), injected at runtime. Leave unset for default admin/admin.
- **Logs**: Container logs go to CloudWatch (`/ecs/{environment}-grafana`).
- **Network**: ALB ingress (80 and 443) from deployer IP or `alb_ingress_cidrs`; tasks accept traffic only from the ALB; EFS accepts NFS only from the task security group.

**SQLite on EFS:** Single ECS task, one writer. For multiple instances or stronger durability, use an external DB (e.g. RDS).

**Persistence:** Dashboards and config are stored in the Grafana DB on EFS. Creating a dashboard and then restarting the service keeps the dashboard.

## Prerequisites

- ECS cluster (EC2 launch type).
- VPC with at least two **private** subnets (for tasks and EFS mount targets) and two **public** subnets (for the ALB).
- **ACM certificate** in the same region as the ALB; cert must cover the Route 53 record name (e.g. grafana.example.com).
- **Route 53 hosted zone** (existing); this stack creates only the A record.

## Apply

```bash
cp terraform.tfvars.example terraform.tfvars
# Set: ecs_cluster_arn, vpc_id, private_subnet_ids, public_subnet_ids, acm_certificate_arn, route53_zone_id, route53_record_name

terraform init
terraform apply
```

## After apply

- **URL**: Use the `web_url` output. Default login is **admin** / **admin** unless you set `grafana_admin_password` in tfvars.
- **Logs**: `log_group_grafana` output gives the CloudWatch log group name.
- **EFS**: `efs_id` is the file system ID; use it for backup/restore of the Grafana data path if needed.
