# Full Alloy config for Database Observability

## PostgreSQL

```alloy
database_observability.postgres "mydb" {
  data_source_name = "postgresql://grafana_monitoring:secret@localhost:5432/mydb?sslmode=disable"

  enable_collectors = ["pg_stat_statements", "query_samples", "schema_details"]

  forward_metrics_to = [prometheus.remote_write.cloud.receiver]
  forward_logs_to    = [loki.write.cloud.receiver]
}

prometheus.remote_write "cloud" {
  endpoint {
    url = sys.env("PROMETHEUS_URL")
    basic_auth {
      username = sys.env("PROMETHEUS_USER")
      password = sys.env("GRAFANA_CLOUD_API_KEY")
    }
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
}
```

## MySQL

```alloy
database_observability.mysql "mydb" {
  data_source_name = "grafana_monitoring:secret@tcp(localhost:3306)/mydb"

  enable_collectors = ["query_samples", "explain_plans", "schema_details"]

  forward_metrics_to = [prometheus.remote_write.cloud.receiver]
  forward_logs_to    = [loki.write.cloud.receiver]
}
```

## Collectors

| Collector | DB | What it produces |
|---|---|---|
| `pg_stat_statements` | PG | Per-query call count + total/mean/p95 latency from `pg_stat_statements` |
| `query_samples` | both | Sampled actual query texts with parameters + per-execution timing |
| `schema_details` | both | Table / index / column metadata for the Query Performance dashboard |
| `explain_plans` | MySQL | Auto-captured `EXPLAIN` output for slow queries |

Disabling collectors reduces metric cardinality + agent overhead — turn off ones you don't need.
