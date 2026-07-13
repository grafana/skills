# Adaptive Signals — config snippets

## Adaptive Metrics aggregation rule (YAML)

```yaml
# Keep only meaningful labels for HTTP histogram; drops pod/container/instance/node
- match: "^http_request_duration_seconds.*"
  action: keep
  match_labels:
    - method
    - status_code
    - service
```

After Apply takes effect within 5 minutes. Recommendations are also exposed via the API:

```bash
curl https://<stack>.grafana.net/api/plugins/grafana-adaptive-metrics-app/resources/v1/recommendations \
  -H "Authorization: Bearer <token>"
```

## Adaptive Logs — drop & sample in Alloy

```alloy
loki.process "filter_logs" {
  forward_to = [loki.write.cloud.receiver]

  // Drop health-check logs
  stage.drop {
    expression = ".*GET /health.*"
  }

  // Drop debug logs
  stage.drop {
    source     = "level"
    expression = "debug"
  }

  // Sample verbose info logs (keep 10%)
  stage.sampling {
    rate   = 0.1
    source = "level"
    value  = "info"
  }
}
```

## Adaptive Traces — tail-sampling in Alloy

```alloy
otelcol.processor.tail_sampling "cost_control" {
  decision_wait = "10s"
  policy {
    name = "keep-errors"
    type = "status_code"
    status_code { status_codes = ["ERROR"] }
  }
  policy {
    name = "keep-slow"
    type = "latency"
    latency { threshold_ms = 1000 }
  }
  policy {
    name = "sample-rest"
    type = "probabilistic"
    probabilistic { sampling_percentage = 5 }
  }
  output {
    traces = [otelcol.exporter.otlp.cloud.input]
  }
}
```

## Cost attribution labels in Alloy

```alloy
prometheus.remote_write "cloud" {
  endpoint {
    url = sys.env("PROMETHEUS_URL")
    basic_auth {
      username = sys.env("PROM_USER")
      password = sys.env("GRAFANA_CLOUD_API_KEY")
    }
  }
  external_labels = {
    team    = "platform",
    project = "checkout-service",
    env     = "production",
  }
}

loki.write "cloud" {
  endpoint {
    url = sys.env("LOKI_URL")
    basic_auth {
      username = sys.env("LOKI_USER")
      password = sys.env("GRAFANA_CLOUD_API_KEY")
    }
  }
  external_labels = {
    team    = "platform",
    project = "checkout-service",
  }
}
```
