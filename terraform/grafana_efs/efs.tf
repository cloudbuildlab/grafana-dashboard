# -----------------------------------------------------------------------------
# EFS for Grafana persistent data (/var/lib/grafana)
# -----------------------------------------------------------------------------
resource "aws_efs_file_system" "grafana" {
  encrypted = true

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-efs" })
}

resource "aws_efs_mount_target" "grafana" {
  for_each = toset(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.grafana.id
  subnet_id       = each.key
  security_groups = [aws_security_group.efs.id]
}

# Access point 472:472 to match Grafana container user; 0755 so only owner can write (no root, no world-writable).
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

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-efs-ap" })
}

resource "aws_security_group" "efs" {
  name        = "${var.environment}-${local.app_name}-efs"
  description = "EFS mount targets for Grafana"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.tasks.id]
    description     = "NFS from ECS tasks"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-efs" })
}
