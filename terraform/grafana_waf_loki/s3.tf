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

locals {
  dashboard_files = sort(fileset("${path.module}/templates/dashboards", "*.json"))
}

# Loki single-binary config (limits_config + ruler) — copied onto the Loki data volume at task start.
resource "aws_s3_object" "loki_local_config" {
  bucket       = aws_s3_bucket.bootstrap.id
  key          = "loki/local-config.yaml"
  content_type = "application/yaml"
  source       = "${path.module}/templates/loki-local-config.yaml"
  etag         = filemd5("${path.module}/templates/loki-local-config.yaml")
}

# Loki recording rules — stored in S3 under loki/rules/fake/ (fake = no-auth tenant namespace).
# The ruler evaluates WAF recording rules every 5m so dashboards query pre-aggregated metrics
# (waf_action_requests_total, waf_terminating_rule_requests_total, waf_bucket_acl_requests_total,
#  waf_method_requests_total, waf_client_ip_requests_total, waf_signal_sqli_requests_total, etc.).
resource "aws_s3_object" "loki_rules_waf" {
  bucket       = aws_s3_bucket.bootstrap.id
  key          = "loki/rules/fake/waf.yaml"
  content_type = "application/yaml"
  source       = "${path.module}/templates/loki-rules/waf.yaml"
  etag         = filemd5("${path.module}/templates/loki-rules/waf.yaml")
}

# Grafana datasource provisioning: wires Loki via Cloud Map as the default datasource.
# loki-prometheus: exposes Loki's Prometheus-compatible endpoint so recording rule metrics
# (e.g. waf_uri_requests_total) can be queried with standard PromQL aggregations.
resource "aws_s3_object" "datasource_loki_prom" {
  bucket       = aws_s3_bucket.bootstrap.id
  key          = "grafana/datasources/loki-prometheus.yaml"
  content_type = "application/yaml"

  content = yamlencode({
    apiVersion = 1
    datasources = [{
      name   = "Loki (Prometheus)"
      type   = "prometheus"
      uid    = "loki-prometheus"
      url    = "http://loki.${local.cloud_map_namespace}:3100/loki"
      access = "proxy"
      jsonData = {
        # Match recording rule evaluation interval so Grafana aligns steps correctly.
        timeInterval = "5m"
        httpMethod   = "POST"
        # auth_enabled: false Loki still uses org_id=fake; Prometheus API needs the header.
        httpHeaderName1 = "X-Scope-OrgID"
      }
      secureJsonData = {
        httpHeaderValue1 = "fake"
      }
    }]
  })
}

resource "aws_s3_object" "datasource_loki" {
  bucket       = aws_s3_bucket.bootstrap.id
  key          = "grafana/datasources/loki.yaml"
  content_type = "application/yaml"

  content = yamlencode({
    apiVersion = 1
    datasources = [{
      name   = "Loki"
      type   = "loki"
      uid    = "loki"
      url    = "http://loki.${local.cloud_map_namespace}:3100"
      access = "proxy"
      # Seconds; default ~60s proxy calls can EOF while Loki is still streaming large query_range.
      jsonData = {
        timeout  = 600
        maxLines = 5000
      }
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
      name                  = "WAF"
      orgId                 = 1
      folder                = "WAF"
      type                  = "file"
      disableDeletion       = false
      editable              = true
      updateIntervalSeconds = 10
      options = {
        # JSON only — not the same dir as provider.yaml (Grafana skips or mis-loads otherwise).
        path = "/grafana-data/provisioning/dashboards/waf"
      }
    }]
  })
}

# Dashboard JSON files — dynamically uploaded from local templates directory.
resource "aws_s3_object" "dashboard_json" {
  for_each = toset(local.dashboard_files)

  bucket       = aws_s3_bucket.bootstrap.id
  key          = "grafana/dashboards/${each.value}"
  source       = "${path.module}/templates/dashboards/${each.value}"
  content_type = "application/json"
  etag         = filemd5("${path.module}/templates/dashboards/${each.value}")
}

# Grafana alerting provisioning — SQLi signal alert rule.
resource "aws_s3_object" "alerting_sqli" {
  bucket       = aws_s3_bucket.bootstrap.id
  key          = "grafana/alerting/sqli-alert.yaml"
  content_type = "application/yaml"
  source       = "${path.module}/templates/alerting/sqli-alert.yaml"
  etag         = filemd5("${path.module}/templates/alerting/sqli-alert.yaml")
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
    clients   = [{ url = "http://loki.${local.cloud_map_namespace}:3100/loki/api/v1/push" }]
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
