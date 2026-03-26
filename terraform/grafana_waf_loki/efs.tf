# -----------------------------------------------------------------------------
# EFS for Grafana persistent data (provisioning, DB, plugins, logs)
# Follows the same pattern as terraform/grafana_efs.
# -----------------------------------------------------------------------------
resource "aws_efs_file_system" "grafana" {
  encrypted = true

  tags = merge(var.tags, { Name = "${local.stack_name}-efs" })
}

resource "aws_efs_mount_target" "grafana" {
  for_each = toset(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.grafana.id
  subnet_id       = each.key
  security_groups = [aws_security_group.efs.id]
}

# Access point POSIX 472:472 — matches the Grafana container user so writes persist correctly.
resource "aws_efs_access_point" "grafana" {
  file_system_id = aws_efs_file_system.grafana.id

  posix_user {
    uid = 472
    gid = 472
  }

  root_directory {
    path = "/grafana"
    creation_info {
      owner_uid   = 472
      owner_gid   = 472
      permissions = "0755"
    }
  }

  tags = merge(var.tags, { Name = "${local.stack_name}-efs-ap" })
}

resource "aws_security_group" "efs" {
  name        = "${local.stack_name}-efs"
  description = "EFS mount targets for Grafana"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana_tasks.id, aws_security_group.sync_task.id]
    description     = "NFS from Grafana and sync tasks"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.stack_name}-efs" })
}

# Sync task security group — egress only (S3 via gateway endpoint + EFS).
resource "aws_security_group" "sync_task" {
  name        = "${local.stack_name}-sync-task"
  description = "Dashboard sync task (S3 to EFS): egress only"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.stack_name}-sync-task" })
}
