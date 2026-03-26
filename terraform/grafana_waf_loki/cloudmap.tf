# -----------------------------------------------------------------------------
# AWS Cloud Map — private DNS for Loki (Lambda resolves loki.<namespace> in-VPC)
# -----------------------------------------------------------------------------
resource "aws_service_discovery_private_dns_namespace" "app" {
  name        = local.cloud_map_namespace
  description = "Internal DNS for ${local.app_name}"
  vpc         = var.vpc_id

  tags = merge(var.tags, { Name = local.cloud_map_namespace })
}

resource "aws_service_discovery_service" "loki" {
  name = "loki"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.app.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  tags = merge(var.tags, { Name = "${var.environment}-${local.app_name}-loki" })
}
