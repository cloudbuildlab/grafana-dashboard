# grafana-dashboard

Terraform stacks for running Grafana on AWS (ECS, ALB). Pick a stack and apply from that directory:

```bash
cd terraform/grafana_cognito   # or another stack
terraform init && terraform apply
```

| Stack | Purpose |
| ----- | ------- |
| [grafana_base](terraform/grafana_base/README.md) | Grafana on ECS behind an ALB (HTTP, ephemeral). |
| [grafana_efs](terraform/grafana_efs/README.md) | Grafana on ECS with EFS persistence (HTTP). |
| [grafana_https](terraform/grafana_https/README.md) | Grafana on ECS with HTTPS (ACM), Route 53, and EFS. |
| [grafana_cognito](terraform/grafana_cognito/README.md) | Grafana on ECS with HTTPS, Route 53, EFS, and Cognito SSO + RBAC. |
| [grafana_cognito_ec2](terraform/grafana_cognito_ec2/README.md) | Grafana on EC2 with HTTPS, Route 53, and Cognito SSO + RBAC (demo; data on instance disk). |
