# Key metrics + alert rules

## Key PromQL queries

```promql
# Query rate by database
rate(db_query_total{db_instance="mydb"}[5m])

# P95 query latency
histogram_quantile(0.95, rate(db_query_duration_seconds_bucket[5m]))

# Error rate
rate(db_query_errors_total[5m]) / rate(db_query_total[5m])

# Slow queries (over 1 second)
count(db_query_duration_seconds > 1) by (db_query_digest)

# Active connections
db_connections_active{db_instance="mydb"}
```

## Alert rules

```yaml
groups:
  - name: database-observability
    rules:
      - alert: SlowQueryDetected
        expr: histogram_quantile(0.95, rate(db_query_duration_seconds_bucket[5m])) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "P95 query latency > 1s on {{ $labels.db_instance }}"

      - alert: HighDBErrorRate
        expr: rate(db_query_errors_total[5m]) / rate(db_query_total[5m]) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "DB error rate > 5% on {{ $labels.db_instance }}"

      - alert: TooManyConnections
        expr: db_connections_active / db_connections_max > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "DB connection pool >80% on {{ $labels.db_instance }}"
```

## Trace correlation

Drill from a slow service-latency span to the specific slow SQL that caused it:

- Make sure the application's OTel instrumentation emits `db.statement`, `db.system`, `db.name` span attributes (most DB drivers do this automatically when wrapped in OTel)
- Grafana Cloud links those spans to Database Observability query samples by matching the query digest
- Click through from the trace span → "View query in Database Observability" → see the explain plan
