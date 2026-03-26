# grafana_waf_loki

Terraform stack in the same shape as [grafana_base](../grafana_base/README.md): **existing VPC**, **existing ECS (EC2) cluster**, private subnets for tasks, public subnets for the ALB. Uses the same **`app_name = "grafana"`** naming as `grafana_base` / `grafana_efs` (`{environment}-grafana` for ALB and CloudWatch groups). This stack runs **Grafana**, **Loki**, and a dedicated **WAF worker** service. WAF ingest path is **S3 -> SQS -> ECS worker -> Loki**, with Cloud Map for in-VPC Loki DNS.

## What it does

- **ECS**: Three services on EC2 launch type:
  - `grafana` service with bootstrap + grafana + promtail containers behind ALB.
  - `loki` service with bootstrap + loki containers, registered in Cloud Map as `loki.<namespace>`.
  - `waf-worker` service (single container) that polls SQS and pushes to Loki.
  Deployment safety controls (`ecs_stop_first_deployment`, circuit breaker, AZ rebalancing behavior) are kept from the earlier stack.
- **ALB**: HTTP :80 → Grafana (`aws_lb.app`, `aws_lb_target_group.web`, `aws_lb_listener.app`).
  - Target group deregistration delay defaults to **30s** (`alb_deregistration_delay_seconds`) to avoid long stop-first replacements.
  - Health check interval defaults to **15s** (`alb_healthcheck_interval_seconds`) so new tasks become healthy faster.
- **Loki**: Uses an **ECS-managed EBS volume** per task (configured at service deployment). This avoids consuming container instance root disk for Loki data. Tune with `loki_ebs_size_gb` and `loki_ebs_volume_type`.
- **Bootstrap**: Task-scoped Docker volumes + `public.ecr.aws/aws-cli/aws-cli` sync from the created bootstrap bucket (Grafana datasources/dashboards, Promtail config). Task role has `s3:GetObject` / `ListBucket` on that bucket only.
- **Bootstrap roll Lambda** (optional, default on): Python 3.14, **not** in a VPC. On `s3:ObjectCreated:*` in the bootstrap bucket it calls `ecs:UpdateService` with `forceNewDeployment` for both `grafana` and `loki` services so provisioning sync is re-run after bootstrap object changes.
- **WAF worker**: External image supplied by `waf_worker_image` and `waf_worker_image_tag` (recommended source repo: `~/workspace/platformfuzz/waf-log-worker-image`). Worker is VPC-attached, polls SQS, reads WAF objects from S3, and pushes streams to Loki using `bucket` and `waf_acl` labels.
- **Secrets**: Optional Grafana admin password in SSM — same as `grafana_base`.

## Prerequisites

- ECS cluster (**EC2** launch type), same as `grafana_base`.
- VPC with **private** subnets (tasks) and **public** subnets (ALB).
- Container instances with **`/var/log/ecs`** for Promtail (normal on ECS-optimized AMIs).

**Note:** Do not deploy this stack with the same `environment` value as another `grafana_*` stack in the same account/region, or names will collide (same `{environment}-grafana` prefix).

## Apply

```bash
cd terraform/grafana_waf_loki
cp terraform.tfvars.example terraform.tfvars
# Set: ecs_cluster_arn, vpc_id, private_subnet_ids, public_subnet_ids, waf_logs_bucket_name, waf_worker_image

terraform init
terraform apply
```

## After apply

- **Provisioning updates**: Changing bootstrap bucket content triggers an ECS rollout when `enable_bootstrap_roll_lambda` is true; check `/aws/lambda/{environment}-grafana-bootstrap-roll` logs if needed.
- **URL**: `web_url` output (same idea as `grafana_base`).
- **Logs**: `log_group_grafana` and sibling `/ecs/{environment}-grafana-*` groups. Defaults reduce noise: **`GF_LOG_LEVEL=warn`**, **`GF_SERVER_ROUTER_LOGGING=false`**, and **`-log.level=warn`** on Loki/Promtail (override with **`grafana_log_level`**, **`grafana_router_logging`**, **`loki_log_level`**, **`promtail_log_level`**). For cost, set **CloudWatch retention** on those log groups in AWS or via Terraform if you add it.
- **DLQ**: If ingest fails repeatedly, inspect `sqs_dlq_url`.
