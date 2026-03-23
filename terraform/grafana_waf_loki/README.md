# grafana_waf_loki

Terraform stack in the same shape as [grafana_base](../grafana_base/README.md): **existing VPC**, **existing ECS (EC2) cluster**, private subnets for tasks, public subnets for the ALB. Uses the same **`app_name = "grafana"`** naming as `grafana_base` / `grafana_efs` (`{environment}-grafana` for ALB, ECS service, target group, and log groups). This stack adds **Loki**, **Promtail**, **WAF log ingest** (S3 → SQS → Lambda → Loki), **Cloud Map** for in-VPC Loki DNS, and an **S3 bootstrap bucket** synced by a short-lived **bootstrap** container (AWS CLI).

## What it does

- **ECS**: Multi-container task (bootstrap → Loki → Grafana + Promtail), `awsvpc`, same service pattern as `grafana_base`.
- **ALB**: HTTP :80 → Grafana (`aws_lb.app`, `aws_lb_target_group.web`, `aws_lb_listener.app`).
- **Loki**: Persists to **`/mnt/loki` on the container instance** (`host_path` volume). Your ECS EC2 capacity must provide that path (e.g. mounted disk).
- **Bootstrap**: Task-scoped Docker volumes + `public.ecr.aws/aws-cli/aws-cli` sync from the created bootstrap bucket (Grafana datasources/dashboards, Promtail config). Task role has `s3:GetObject` / `ListBucket` on that bucket only.
- **Lambda**: Node.js 24, VPC-attached in your private subnets, consumes SQS, reads WAF logs from S3, pushes to Loki via `http://loki.<namespace>.local:3100/...`.
- **Secrets**: Optional Grafana admin password in SSM — same as `grafana_base`.

## Prerequisites

- ECS cluster (**EC2** launch type), same as `grafana_base`.
- VPC with **private** subnets (tasks + Lambda) and **public** subnets (ALB).
- Container instances with **`/mnt/loki`** created (and writable by Loki’s container user, uid **10001**) and **`/var/log/ecs`** present for Promtail (normal on ECS-optimized AMIs).

**Note:** Do not deploy this stack with the same `environment` value as another `grafana_*` stack in the same account/region, or names will collide (same `{environment}-grafana` prefix).

## Apply

```bash
cd terraform/grafana_waf_loki
cp terraform.tfvars.example terraform.tfvars
# Set: ecs_cluster_arn, vpc_id, private_subnet_ids, public_subnet_ids, waf_logs_bucket_name

terraform init
terraform apply
```

## After apply

- **URL**: `web_url` output (same idea as `grafana_base`).
- **Logs**: `log_group_grafana` and sibling `/ecs/{environment}-grafana-*` groups.
- **DLQ**: If ingest fails repeatedly, inspect `sqs_dlq_url`.
