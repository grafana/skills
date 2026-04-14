---
name: cost-management
license: Apache-2.0
description: >
  Grafana Cloud cost management — usage monitoring, cost attribution by label, usage alerts, invoice
  management, and optimization strategies. Covers Adaptive Metrics (cardinality reduction), Adaptive
  Logs (log filtering), cost attribution labels, and the FOCUS-compliant billing application.
  Use when analyzing Grafana Cloud spending, setting up cost alerts, attributing costs to teams,
  reducing metric/log cardinality, or forecasting observability budgets.
---

# Grafana Cloud Cost Management

> **Docs**: https://grafana.com/docs/grafana-cloud/cost-management-and-billing/

## Cost Management & Billing Application

Access: **My Account → Cost Management** (or within your Grafana Cloud stack)

FOCUS-compliant (FinOps Open Cost and Usage Specification) billing dashboards showing:
- Spending by signal type (metrics, logs, traces, profiles)
- Month-over-month trends
- Usage vs. quota tracking
- Invoice download

## Cost Attribution by Label

Tag your telemetry at ingestion to enable per-team cost reporting:

```alloy
// Add cost attribution labels in Alloy
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

## Usage Alerts

Set alerts before you hit quota or budget thresholds:

```yaml
# Alert when approaching metrics quota
groups:
  - name: grafana-cloud-usage
    rules:
      - alert: MetricsUsageHigh
        expr: grafana_cloud_metrics_active_series / grafana_cloud_metrics_limit > 0.8
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Grafana Cloud metrics usage >80% of quota"

      - alert: LogsIngestionHigh
        expr: increase(grafana_cloud_logs_bytes_ingested_total[24h]) > 50e9  # 50GB/day
        labels:
          severity: warning
        annotations:
          summary: "Grafana Cloud log ingestion >50GB today"
```

## Adaptive Metrics (Reduce Cardinality)

Automatically identifies unused or high-cardinality metrics and generates aggregation rules.

```bash
# View recommendations
curl https://yourstack.grafana.net/api/plugins/grafana-adaptive-metrics-app/resources/v1/recommendations \
  -H "Authorization: Bearer <token>"
```

```yaml
# Apply aggregation rule — drops high-cardinality labels from a metric
- match: "^http_request_duration_seconds.*"
  action: keep
  match_labels:
    - method
    - status_code
    - service
  # Drops: pod, container, instance, node — reduces series from 10k → 50
```

**Workflow:**
1. Go to **Grafana Cloud → Adaptive Metrics**
2. Review recommended aggregation rules (sorted by series reduction impact)
3. Test rules in "Preview" mode before applying
4. Apply rules — takes effect within 5 minutes

## Adaptive Logs (Reduce Log Volume)

Drop or sample log lines before ingestion using Loki's pipeline stages in Alloy:

```alloy
loki.process "filter_logs" {
  forward_to = [loki.write.cloud.receiver]

  // Drop health check logs (high volume, low value)
  stage.drop {
    expression = ".*GET /health.*"
  }

  // Drop debug logs in production
  stage.drop {
    source     = "level"
    expression = "debug"
  }

  // Sample verbose info logs (keep 10%)
  stage.sampling {
    rate = 0.1
    source = "level"
    value  = "info"
  }
}
```

## Adaptive Traces (Reduce Trace Volume)

Use Alloy tail-based sampling to keep only important traces:

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

## Key Metrics for Cost Monitoring

```promql
# Active metric series (billed unit for metrics)
grafana_cloud_metrics_active_series

# Series by label (find high-cardinality sources)
topk(20, count by (__name__) ({__name__=~".+"}))

# Log bytes ingested per stream
sum(increase(loki_ingester_chunk_size_bytes_sum[24h])) by (namespace, app)

# Trace spans ingested
rate(tempo_distributor_spans_received_total[5m])
```

## Optimization Checklist

- [ ] Run Adaptive Metrics recommendations — typically reduces series 40-60%
- [ ] Drop health/readiness probe logs in Alloy pipeline
- [ ] Set sampling rate for traces (5-10% is typical for most workloads)
- [ ] Review top-N high-cardinality metrics: `topk(20, count by (__name__))`
- [ ] Add cost attribution labels (`team`, `project`) to all Alloy configs
- [ ] Set usage alerts at 80% of quota
- [ ] Review and clean up unused dashboards and data sources (they don't reduce cost but indicate stale collection)
- [ ] Use recording rules to pre-aggregate expensive PromQL queries

## Understanding Grafana Cloud Pricing

| Signal | Billing Unit |
|--------|-------------|
| Metrics | Active series (unique label combinations) |
| Logs | Bytes ingested |
| Traces | Spans ingested |
| Profiles | Bytes ingested |
| Synthetic Monitoring | Check executions |
| k6 | VUh (Virtual User hours) |
