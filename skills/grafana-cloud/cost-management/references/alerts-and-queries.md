# Usage alerts and cost queries

## Usage alerts (Prometheus rules)

```yaml
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

## Cost-finding PromQL

```promql
# Active series (billing unit for metrics)
grafana_cloud_metrics_active_series

# Top 20 highest-cardinality metric names
topk(20, count by (__name__) ({__name__=~".+"}))

# Log bytes ingested per stream
sum(increase(loki_ingester_chunk_size_bytes_sum[24h])) by (namespace, app)

# Trace spans ingested
rate(tempo_distributor_spans_received_total[5m])
```

## Billing units

| Signal | Billing Unit |
|--------|--------------|
| Metrics | Active series (unique label combinations) |
| Logs | Bytes ingested |
| Traces | Spans ingested |
| Profiles | Bytes ingested |
| Synthetic Monitoring | Check executions |
| k6 | VUh (Virtual User hours) |
