# Adaptive Metrics API + rule formats

Base URL: `https://adaptive-metrics.grafana.net/api/v1`
Auth: `Authorization: Bearer <grafana-cloud-API-key>` (scope `metrics:write`)

## List recommendations

```bash
curl -s -H "Authorization: Bearer <KEY>" \
  "https://adaptive-metrics.grafana.net/api/v1/recommendations" | \
  jq '.recommendations[] | {metric_name, current_series, projected_series, estimated_reduction_percent}'
```

## Apply / disable a recommendation

```bash
# Apply by ID
curl -s -X POST -H "Authorization: Bearer <KEY>" \
  "https://adaptive-metrics.grafana.net/api/v1/recommendations/<ID>/apply"

# Roll back — list rules, then DELETE the offending rule
curl -s -H "Authorization: Bearer <KEY>" \
  "https://adaptive-metrics.grafana.net/api/v1/rules" | jq
curl -s -X DELETE -H "Authorization: Bearer <KEY>" \
  "https://adaptive-metrics.grafana.net/api/v1/rules/<RULE_ID>"
```

## Create a custom rule (exact match)

```bash
curl -s -X POST -H "Authorization: Bearer <KEY>" -H "Content-Type: application/json" \
  "https://adaptive-metrics.grafana.net/api/v1/rules" \
  -d '{
    "rules": [{
      "metric_name": "process_cpu_seconds_total",
      "match_type":  "MATCH_TYPE_EXACT",
      "drop_labels": ["version", "go_version"],
      "aggregations":[{"type":"AGGREGATION_TYPE_SUM"}]
    }]
  }'
```

## Create a regex-match rule (family)

```bash
curl -s -X POST -H "Authorization: Bearer <KEY>" -H "Content-Type: application/json" \
  "https://adaptive-metrics.grafana.net/api/v1/rules" \
  -d '{
    "rules": [{
      "metric_name": "go_.*",
      "match_type":  "MATCH_TYPE_REGEX",
      "drop_labels": ["go_version", "version", "service_instance_id"],
      "aggregations":[{"type":"AGGREGATION_TYPE_SUM"}]
    }]
  }'
```

## Aggregation types

| Type | Use case |
|---|---|
| `sum` | Counters, request counts, byte totals |
| `max` | Gauges where you want the worst-case |
| `min` | Gauges where you want the best-case |
| `avg` | Rate metrics / averages |

**Counters MUST use `sum`** — averaging counters produces incorrect rates.

## Unused metrics — usage analysis

```bash
curl -s -H "Authorization: Bearer <KEY>" \
  "https://adaptive-metrics.grafana.net/api/v1/usage-analysis?filter=unused" | \
  jq '.metrics[] | {metric_name, series_count, last_queried}'
```

Before dropping unused metrics entirely:
1. Confirm not used in any dashboard (search dashboard JSON by metric name).
2. Confirm not used in any alert or recording rule.
3. Check with the owning team — could be an SLO input.

## Alloy fallback — drop at remote_write

```alloy
prometheus.remote_write "grafana_cloud" {
  endpoint {
    url = "https://prometheus-prod-XX.grafana.net/api/prom/push"
    write_relabel_config {
      source_labels = ["__name__"]
      regex         = "unused_metric_name|another_unused_metric"
      action        = "drop"
    }
  }
}
```

## Common labels safe to drop globally

- `version`, `app_version`, `go_version` — rarely queried in PromQL
- `service_instance_id`, `pod_uid`, `container_id` — ultra-high cardinality
- `git_commit`, `build_date` — static, inflate series for no query value

## Adaptive Logs (companion)

```bash
curl -s -H "Authorization: Bearer <KEY>" \
  "https://adaptive-logs.grafana.net/api/v1/recommendations" | \
  jq '.recommendations[] | {stream_selector, estimated_reduction_percent}'
```
