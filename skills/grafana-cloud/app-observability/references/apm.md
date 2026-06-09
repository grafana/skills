# Application Observability (APM)

## What you get

- **Service Inventory** — RED metrics for every service
- **Service Overview** — per-service RED + top operations + error breakdown
- **Service Map** — node graph of dependencies (`span.kind=CLIENT/SERVER` for direction)
- **Operations view** — per-endpoint p50 / p95 / p99 latency

## How metrics are generated

Metrics come from **spanmetrics** (NOT from Prometheus scrape):

- Source: OTel traces sent to Tempo or Alloy
- Generator: Tempo metrics-generator (Cloud default) OR the `spanmetrics` connector in Alloy / OTel Collector
- Stored in Mimir

Key metric names:

| Source | Metric |
|--------|--------|
| Tempo metrics-generator | `traces_spanmetrics_calls_total`, `traces_spanmetrics_duration_seconds` |
| OTel Collector connector | `traces_span_metrics_calls_total`, `traces_span_metrics_duration_seconds` |
| Service Graph | `traces_service_graph_request_total`, `traces_service_graph_request_failed_total` |

## Required OTel resource attributes

| Attribute | Grafana label | Purpose |
|---|---|---|
| `service.name` | `service_name` / part of `job` | service identifier |
| `service.namespace` | part of `job` | groups services; `job = namespace/service.name` |
| `deployment.environment` | `deployment_environment` | env filter |

Recommended: `service.version`, `k8s.cluster.name`, `k8s.namespace.name`, `cloud.region`.

## OTel SDK env vars

```bash
export OTEL_SERVICE_NAME="my-api"
export OTEL_RESOURCE_ATTRIBUTES="service.namespace=myteam,deployment.environment=production,service.version=1.2.3"
export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4317"
export OTEL_EXPORTER_OTLP_PROTOCOL="grpc"
```

## Alloy config (River)

```alloy
otelcol.receiver.otlp "default" {
  grpc { endpoint = "0.0.0.0:4317" }
  http { endpoint = "0.0.0.0:4318" }
  output {
    metrics = [otelcol.processor.resourcedetection.default.input]
    logs    = [otelcol.processor.resourcedetection.default.input]
    traces  = [otelcol.processor.resourcedetection.default.input]
  }
}

otelcol.processor.resourcedetection "default" {
  detectors = ["env", "system", "gcp", "aws", "azure"]
  output {
    metrics = [otelcol.processor.batch.default.input]
    logs    = [otelcol.processor.batch.default.input]
    traces  = [otelcol.processor.batch.default.input]
  }
}

otelcol.processor.batch "default" {
  output {
    metrics = [otelcol.exporter.otlphttp.grafana_cloud.input]
    logs    = [otelcol.exporter.otlphttp.grafana_cloud.input]
    traces  = [otelcol.exporter.otlphttp.grafana_cloud.input]
  }
}

otelcol.auth.basic "grafana_cloud" {
  username = env("GRAFANA_CLOUD_INSTANCE_ID")
  password = env("GRAFANA_CLOUD_API_KEY")
}

otelcol.exporter.otlphttp "grafana_cloud" {
  client {
    endpoint = env("GRAFANA_CLOUD_OTLP_ENDPOINT")
    auth     = otelcol.auth.basic.grafana_cloud.handler
  }
}
```

Required env:

```bash
GRAFANA_CLOUD_OTLP_ENDPOINT=https://otlp-gateway-<region>.grafana.net/otlp
GRAFANA_CLOUD_INSTANCE_ID=<your-instance-id>
GRAFANA_CLOUD_API_KEY=<your-api-key>
```

## Correlation links (built-in)

- Metric spike → exemplar trace in Tempo
- Service Overview → Logs panel (joined by `service.name`)
- Service Overview → "Go to profiles" when Pyroscope configured
- App Observability ↔ Frontend Observability for same service
