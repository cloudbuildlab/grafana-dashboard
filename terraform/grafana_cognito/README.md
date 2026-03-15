# grafana_cognito

Terraform stack that runs **Grafana on ECS** behind an **Application Load Balancer** with **HTTPS** (ACM), **Route 53**, and **Cognito SSO** with RBAC. Persistent storage on EFS.

## What it does

- **ECS**: One task definition (single Grafana container, 512 CPU / 1024 MiB). Service runs in your existing EC2-type ECS cluster, in private subnets. Container runs as non-root (UID 472). ECS Exec enabled for debugging when the cluster supports it.
- **ALB**: HTTPS listener on 443 (existing ACM cert); HTTP on 80 redirects to HTTPS. Health checks use Grafana’s `/api/health` (HTTP 200).
- **Route 53**: Creates an A alias record in an existing hosted zone pointing at the ALB. Set `route53_zone_id` and `route53_record_name`; the zone must already exist.
- **Cognito SSO**: Cognito User Pool as OIDC provider; Grafana uses Generic OAuth. **RBAC**: A Pre Token Generation Lambda injects `grafana_role` (Admin/Editor/Viewer) from Cognito groups `grafana-admins`, `grafana-editors`, `grafana-viewers`. Users not in any of these groups are denied login (strict mode).
- **EFS**: Grafana’s data lives on EFS at `/grafana-data`. SQLite DB, dashboards, plugins, logs, and provisioning dirs persist across task replacement.
- **Secrets**: Optional admin password and Cognito app client secret in SSM Parameter Store (SecureString), injected at runtime. Leave admin password unset for default admin/admin; local login can be kept as fallback or disabled.
- **Logs**: Container logs go to CloudWatch (`/ecs/{environment}-grafana`).
- **Network**: ALB ingress (80 and 443) from deployer IP or `alb_ingress_cidrs`; tasks accept traffic only from the ALB; EFS accepts NFS only from the task security group.

**SQLite on EFS:** Single ECS task, one writer. For multiple instances or stronger durability, use an external DB (e.g. RDS).

**Persistence:** Dashboards and config are stored in the Grafana DB on EFS. Creating a dashboard and then restarting the service keeps the dashboard.

## Auth process

Cognito is the OIDC provider; Grafana uses Generic OAuth. A Pre Token Generation Lambda adds a `grafana_role` claim to the ID token from Cognito group membership; Grafana reads that claim for RBAC (strict mode: no role = login denied).

**Flow:**

```mermaid
sequenceDiagram
    participant User
    participant Grafana
    participant Cognito
    participant PreTokenLambda

    User->>Grafana: GET / (or click "Login with Cognito")
    Grafana->>User: 302 to Cognito /oauth2/authorize
    Note over Grafana,Cognito: client_id, redirect_uri=/login/generic_oauth, scope=openid profile email

    User->>Cognito: Authorize (login if needed)
    Cognito->>Cognito: Resolve user + groups

    Cognito->>PreTokenLambda: Pre Token Generation (event with groups)
    PreTokenLambda->>PreTokenLambda: groups → grafana_role (Admin/Editor/Viewer)
    PreTokenLambda->>Cognito: event + claimsOverrideDetails.grafana_role

    Cognito->>Cognito: Build ID token with claim grafana_role
    Cognito->>User: 302 to Grafana /login/generic_oauth?code=...

    User->>Grafana: GET /login/generic_oauth?code=...
    Grafana->>Cognito: POST /oauth2/token (code + client_secret)
    Cognito->>Grafana: id_token, access_token, refresh_token

    Grafana->>Grafana: Decode id_token, read grafana_role
    Note over Grafana: Strict mode: no role → deny
    Grafana->>User: 302 / or "Login denied"
```

**Role from groups:**

```mermaid
flowchart LR
    subgraph cognito [Cognito]
        Groups["User groups\n(grafana-admins / editors / viewers)"]
        Lambda["Pre Token Lambda"]
        Token["ID token"]
    end
    Groups --> Lambda
    Lambda -->|"claimsToAddOrOverride.grafana_role"| Token
    Token -->|"Grafana reads claim"| Grafana["Grafana RBAC\n(Admin / Editor / Viewer)"]
```

| Step | Where | What |
| ---- | ------ | ---- |
| 1–2 | Grafana | Generic OAuth redirects to Cognito `/oauth2/authorize` with client_id, redirect_uri, scopes. |
| 3–4 | Cognito | User signs in; Cognito resolves user and groups. |
| 5–6 | Pre Token Lambda | Cognito invokes Lambda with groups; Lambda sets `grafana_role` (Admin/Editor/Viewer) in `claimsToAddOrOverride`. |
| 7 | Cognito | ID token is issued with `grafana_role`; redirect to Grafana with auth code. |
| 8–9 | Grafana | Exchanges code for tokens, reads `grafana_role` from ID token, applies RBAC; strict mode denies if role is missing. |

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

- **URL**: Use the `web_url` output. Sign in via **Login with Cognito** (or use local admin if `grafana_admin_password` is set and login form is enabled).
- **Cognito**: Create users in the user pool (console, CLI, or Terraform). Add each user to one of `grafana-admins`, `grafana-editors`, or `grafana-viewers` for RBAC. Outputs `cognito_user_pool_id`, `cognito_user_pool_domain`, and `cognito_app_client_id` for reference.

### Creating users (optional)

Set the `cognito_users` variable; Terraform creates each user, adds them to the specified group, and Cognito sends a welcome email with a temporary password.

Example (see `terraform.tfvars.example`):

```hcl
cognito_users = {
  "grafana-admins"  = [{ email = "admin@example.com", name = "Admin User" }]
  "grafana-editors" = [{ email = "editor@example.com" }]
  "grafana-viewers" = [{ email = "viewer@example.com", name = "Viewer" }]
}
```

- **Logs**: `log_group_grafana` output gives the CloudWatch log group name.
- **EFS**: `efs_id` is the file system ID; use it for backup/restore of the Grafana data path if needed.
