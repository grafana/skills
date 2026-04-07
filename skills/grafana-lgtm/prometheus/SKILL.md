---
name: prometheus
license: Apache-2.0
description: >
  Prometheus and Grafana Cloud Metrics overview including PromQL query language, Metrics Drilldown,
  alerting, recording rules, and integration patterns. Use when working with Prometheus, writing PromQL
  queries, configuring alerting, or discussing metrics architecture and best practices.
---

# Metrics with Prometheus and Grafana

## Value Proposition

Prometheus is an open-source monitoring and alerting toolkit for cloud-native environments. Combined with
Grafana Cloud Metrics (powered by Grafana Mimir), it provides a fully managed Prometheus-compatible service
with long-term storage, global query performance, and enterprise scalability.

**Key Differentiators**: Pull-based model, dimensional data model with labels, PromQL, automatic service
discovery, scales to billions of active series.

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

## Metrics Drilldown

Queryless Prometheus metrics exploration (preinstalled in Grafana 12+):
- Browse metrics without writing PromQL
- Smart segmentation and anomaly detection
- Auto-visualization with optimal chart types
- Metric relationship discovery
- Telemetry pivoting (metrics to logs)

## Alerting

### Prometheus Alertmanager
Route, group, silence, and deduplicate alerts. Multi-destination routing (PagerDuty, Slack, Email, webhooks).

### Grafana Alerting
Unified alerting across all data sources. Supports multi-dimensional alerts, notification policies,
and contact points.

### Recording Rules
Pre-compute expensive PromQL queries for dashboard performance:

```yaml
groups:
  - name: api_rules
    rules:
      - record: job:http_requests:rate5m
        expr: sum by (job) (rate(http_requests_total[5m]))
```

## Architecture

- **Pull-based scraping**: Prometheus scrapes HTTP endpoints at configured intervals
- **Service discovery**: Automatic target discovery for K8s, EC2, Consul
- **Push gateway**: For short-lived jobs that can't be scraped
- **Remote write/read**: Send metrics to Grafana Cloud, Thanos, Mimir
- **Local storage**: Efficient on-disk time-series database

## Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [PromQL Reference](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Cloud Metrics](https://grafana.com/docs/grafana-cloud/send-data/metrics/)
- [Metrics Drilldown App](https://github.com/grafana/metrics-drilldown)
- [Grafana Alerting](https://grafana.com/docs/grafana/latest/alerting/)
- [Grafana Mimir](https://grafana.com/docs/mimir/latest/)
