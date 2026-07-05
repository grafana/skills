---
name: prometheus
license: Apache-2.0
description: >
  Prometheus and Grafana Cloud Metrics overview including PromQL query language, Metrics Drilldown,
  alerting, recording rules, and integration patterns. Use when working with Prometheus, writing PromQL
  queries, configuring alerting, or discussing metrics architecture and best practices.
---

# Metrics with Prometheus and Grafana

> **Docs**: https://prometheus.io/docs/ | **Grafana Cloud Metrics**: https://grafana.com/docs/grafana-cloud/send-data/metrics/

## PromQL Quick Reference

### Instant Vector Selectors

```promql
# By metric name
http_requests_total

# Label filter
http_requests_total{job="api-server"}

# Multiple labels (AND)
http_requests_total{job="api-server", method="GET"}

# Regex
http_requests_total{job=~"api.*", status=~"5.."}

# Negative
http_requests_total{status!="200"}
```

### Range Vectors & Rates

```promql
# Per-second rate over 5 minutes
rate(http_requests_total[5m])

# Increase over interval
increase(http_requests_total[1h])

# Instant rate (last two samples)
irate(http_requests_total[5m])

# Offset (5 minutes ago)
rate(http_requests_total[5m] offset 5m)
```

### Aggregations

```promql
# Sum by label
sum by (job) (rate(http_requests_total[5m]))

# Average
avg by (instance) (node_cpu_seconds_total)

# Top-K
topk(5, rate(http_requests_total[5m]))

# Histogram quantiles
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# Count distinct
count(up{job="api"})
```

### Common Patterns

```promql
# Error rate percentage
sum(rate(http_requests_total{status=~"5.."}[5m]))
  / sum(rate(http_requests_total[5m])) * 100

# Saturation (CPU usage %)
100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes

# Predict disk full (linear extrapolation)
predict_linear(node_filesystem_free_bytes[6h], 24*3600) < 0
```

## Alerting Rules

### Prometheus Alerting Rule

```yaml
groups:
  - name: api_alerts
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m]))
            / sum(rate(http_requests_total[5m])) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High 5xx error rate ({{ $value | humanizePercentage }})"
```

### Alertmanager Routing

```yaml
# alertmanager.yml
route:
  receiver: default
  group_by: [alertname, job]
  group_wait: 30s
  group_interval: 5m
  routes:
    - match:
        severity: critical
      receiver: pagerduty
    - match:
        severity: warning
      receiver: slack

receivers:
  - name: pagerduty
    pagerduty_configs:
      - service_key: "<key>"
  - name: slack
    slack_configs:
      - channel: "#alerts"
        api_url: "<webhook_url>"
  - name: default
    email_configs:
      - to: "oncall@example.com"
```

### Validate Alerting Configuration

```bash
promtool check rules rules.yml
amtool check-config alertmanager.yml
amtool config routes test --config.file=alertmanager.yml severity=critical
```

## Recording Rules

Pre-compute expensive PromQL for dashboard performance:

```yaml
groups:
  - name: api_rules
    interval: 1m
    rules:
      - record: job:http_requests:rate5m
        expr: sum by (job) (rate(http_requests_total[5m]))
      - record: job:http_request_duration_seconds:p99
        expr: histogram_quantile(0.99, sum by (job, le) (rate(http_request_duration_seconds_bucket[5m])))
```

### Deploy and Verify Recording Rules

```bash
# 1. Validate rule syntax
promtool check rules rules/recording.yml

# 2. Reload Prometheus (after adding to rule_files in prometheus.yml)
curl -X POST http://localhost:9090/-/reload

# 3. Verify rules are active
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | {name, health}'
```

## Metrics Drilldown (Grafana 12+)

Queryless Prometheus exploration — browse metrics without writing PromQL. Navigate to
**Explore > Metrics Drilldown** or use `<grafana-url>/a/grafana-metricsdrilldown-app`.
Provides metric search with label breakdown, smart segmentation for anomaly detection,
auto-visualization, and telemetry pivoting from metrics to related logs and traces.

## Resources

- [PromQL Reference](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Cloud Metrics](https://grafana.com/docs/grafana-cloud/send-data/metrics/)
- [Metrics Drilldown App](https://github.com/grafana/metrics-drilldown)
- [Grafana Alerting](https://grafana.com/docs/grafana/latest/alerting/)
- [Grafana Mimir](https://grafana.com/docs/mimir/latest/)
