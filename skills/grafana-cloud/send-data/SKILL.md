---
name: send-data
license: Apache-2.0
description: >
  Sending telemetry data to Grafana Cloud — metrics via Prometheus remote write or OTLP, logs via
  Loki push or Alloy, traces via OTLP to Tempo, profiles via Pyroscope. Covers Alloy-based pipelines,
  direct SDK/agent integrations, cloud integrations catalog, and credentials management.
  Use when connecting an application or infrastructure to Grafana Cloud, setting up data ingestion,
  configuring remote write, or choosing between ingestion methods.
---

# Sending Data to Grafana Cloud

> **Docs**: https://grafana.com/docs/grafana-cloud/send-data/

## Quick Start: Find Your Credentials

In Grafana Cloud portal → **My Account** → **Stack** → **Details**:

| Signal | Credential Fields |
|--------|------------------|
| Metrics | Prometheus remote write URL, username, password/API key |
| Logs | Loki URL, username, password/API key |
| Traces | Tempo OTLP endpoint, username, password/API key |
| Profiles | Pyroscope URL, username, password/API key |

## Alloy (Recommended — All Signals)

```alloy
// METRICS
prometheus.scrape "app" {
  targets    = [{"__address__" = "localhost:8080"}]
  forward_to = [prometheus.remote_write.cloud.receiver]
}

prometheus.remote_write "cloud" {
  endpoint {
    url = "https://prometheus-prod-xx.grafana.net/api/prom/push"
    basic_auth {
      username = sys.env("PROM_USER")
      password = sys.env("GRAFANA_CLOUD_API_KEY")
    }
  }
}

// LOGS
loki.source.file "app" {
  targets = [{__path__ = "/var/log/app/*.log", job = "app"}]
  forward_to = [loki.write.cloud.receiver]
}

loki.write "cloud" {
  endpoint {
    url = "https://logs-prod-xx.grafana.net/loki/api/v1/push"
    basic_auth {
      username = sys.env("LOKI_USER")
      password = sys.env("GRAFANA_CLOUD_API_KEY")
    }
  }
}

// TRACES (OTLP receive → forward)
otelcol.receiver.otlp "default" {
  grpc { endpoint = "0.0.0.0:4317" }
  http { endpoint = "0.0.0.0:4318" }
  output {
    traces = [otelcol.exporter.otlp.cloud.input]
  }
}

otelcol.exporter.otlp "cloud" {
  client {
    endpoint = "tempo-prod-xx.grafana.net:443"
    auth = otelcol.auth.basic.cloud.handler
  }
}

otelcol.auth.basic "cloud" {
  username = sys.env("TEMPO_USER")
  password = sys.env("GRAFANA_CLOUD_API_KEY")
}
```

## Direct Prometheus Remote Write

```yaml
# prometheus.yml
remote_write:
  - url: https://prometheus-prod-xx.grafana.net/api/prom/push
    basic_auth:
      username: "123456"
      password: "your-api-key"
    write_relabel_configs:
      - source_labels: [__name__]
        regex: "go_.*"
        action: drop   # optional: drop high-cardinality metrics
```

## Direct Loki Push (curl)

```bash
curl -X POST https://logs-prod-xx.grafana.net/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -u "123456:your-api-key" \
  -d '{
    "streams": [{
      "stream": { "app": "myapp", "env": "prod" },
      "values": [
        ["1706745600000000000", "application started"]
      ]
    }]
  }'
```

## OpenTelemetry SDK → Grafana Cloud

```bash
# Environment variables for OTLP export
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp-gateway-prod-xx.grafana.net/otlp"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic $(echo -n '123456:your-api-key' | base64)"
export OTEL_SERVICE_NAME="my-service"
```

Python example:
```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

provider = TracerProvider()
exporter = OTLPSpanExporter()  # reads OTEL_EXPORTER_OTLP_* env vars
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
```

## Cloud Integrations

Pre-built integrations for common infrastructure (install from Grafana Cloud UI or API):

```bash
# List available integrations
curl https://integrations-api-prod.grafana.net/api/v1/integrations \
  -H "Authorization: Bearer <api-key>"

# Install AWS CloudWatch integration
curl -X POST https://integrations-api-prod.grafana.net/api/v1/integrations/cloudwatch \
  -H "Authorization: Bearer <api-key>" \
  -H "Content-Type: application/json" \
  -d '{"name": "aws-prod", "config": {...}}'
```

Popular integrations: AWS CloudWatch, Azure Monitor, GCP, Kubernetes, Docker, MySQL, PostgreSQL, Redis, Nginx, Apache, JVM, Node.js, Python, .NET.

## Kubernetes Agent Operator

```yaml
# values.yaml for grafana/k8s-monitoring Helm chart
cluster:
  name: production

externalServices:
  prometheus:
    host: https://prometheus-prod-xx.grafana.net
    basicAuth:
      username: "123456"
      password:
        secretName: grafana-cloud-secret
        secretKey: api-key

  loki:
    host: https://logs-prod-xx.grafana.net
    basicAuth:
      username: "234567"
      password:
        secretName: grafana-cloud-secret
        secretKey: api-key

metrics:
  enabled: true
  podMonitors:
    enabled: true
  serviceMonitors:
    enabled: true

logs:
  pod_logs:
    enabled: true

traces:
  enabled: true
```

```bash
helm install k8s-monitoring grafana/k8s-monitoring \
  -n monitoring --create-namespace \
  -f values.yaml
```

## API Key Management

```bash
# Create API key via Grafana API
curl -X POST https://yourstack.grafana.net/api/auth/keys \
  -H "Content-Type: application/json" \
  -u "admin:adminpassword" \
  -d '{"name": "alloy-writer", "role": "MetricsPublisher", "secondsToLive": 0}'
```

Roles for data ingestion: `MetricsPublisher`, `LogsPublisher`, `TracesPublisher`, `ProfilesPublisher`
