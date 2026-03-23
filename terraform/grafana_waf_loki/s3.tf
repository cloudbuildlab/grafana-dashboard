# -----------------------------------------------------------------------------
# S3 bootstrap bucket — Grafana provisioning files (datasource + dashboards)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "bootstrap" {
  bucket_prefix = "${local.stack_name}-bootstrap-"

  tags = merge(var.tags, { Name = "${local.stack_name}-bootstrap" })
}

resource "aws_s3_bucket_public_access_block" "bootstrap" {
  bucket = aws_s3_bucket.bootstrap.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bootstrap" {
  bucket = aws_s3_bucket.bootstrap.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Grafana datasource provisioning: wires Loki at localhost:3100 as the default datasource.
resource "aws_s3_object" "datasource_loki" {
  bucket       = aws_s3_bucket.bootstrap.id
  key          = "grafana/datasources/loki.yaml"
  content_type = "application/yaml"

  content = yamlencode({
    apiVersion = 1
    datasources = [{
      name      = "Loki"
      type      = "loki"
      uid       = "loki"
      url       = "http://localhost:3100"
      access    = "proxy"
      isDefault = true
    }]
  })
}

# Grafana dashboard provisioner: loads JSON files from the provisioning directory.
resource "aws_s3_object" "dashboard_provider" {
  bucket       = aws_s3_bucket.bootstrap.id
  key          = "grafana/dashboards/provider.yaml"
  content_type = "application/yaml"

  content = yamlencode({
    apiVersion = 1
    providers = [{
      name            = "WAF"
      orgId           = 1
      folder          = "WAF"
      type            = "file"
      disableDeletion = false
      editable        = true
      options = {
        path = "/etc/grafana/provisioning/dashboards"
      }
    }]
  })
}

# Dashboard JSON files — uploaded from local templates directory.
resource "aws_s3_object" "dashboard_waf" {
  bucket       = aws_s3_bucket.bootstrap.id
  key          = "grafana/dashboards/waf.json"
  source       = "${path.module}/templates/dashboards/waf.json"
  content_type = "application/json"
  etag         = filemd5("${path.module}/templates/dashboards/waf.json")
}

resource "aws_s3_object" "dashboard_waf_overview" {
  bucket       = aws_s3_bucket.bootstrap.id
  key          = "grafana/dashboards/waf-overview.json"
  source       = "${path.module}/templates/dashboards/waf-overview.json"
  content_type = "application/json"
  etag         = filemd5("${path.module}/templates/dashboards/waf-overview.json")
}

resource "aws_s3_object" "dashboard_waf_geomap" {
  bucket       = aws_s3_bucket.bootstrap.id
  key          = "grafana/dashboards/waf-geomap.json"
  source       = "${path.module}/templates/dashboards/waf-geomap.json"
  content_type = "application/json"
  etag         = filemd5("${path.module}/templates/dashboards/waf-geomap.json")
}

# Promtail config: scrapes ECS agent log files on the host.
resource "aws_s3_object" "promtail_config" {
  bucket       = aws_s3_bucket.bootstrap.id
  key          = "promtail/config.yaml"
  content_type = "application/yaml"

  content = yamlencode({
    server = {
      http_listen_port = 9080
      grpc_listen_port = 0
    }
    positions = { filename = "/tmp/positions.yaml" }
    clients   = [{ url = "http://localhost:3100/loki/api/v1/push" }]
    scrape_configs = [{
      job_name = "ecs-agent"
      static_configs = [{
        targets = ["localhost"]
        labels = {
          job      = "ecs-agent"
          __path__ = "/var/log/ecs/*.log"
        }
      }]
    }]
  })
}
