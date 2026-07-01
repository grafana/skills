---
name: adaptive-metrics
license: Apache-2.0
description: Cut Grafana Cloud Metrics cost by shrinking active-series count with Adaptive Metrics aggregation rules — auto-recommendations from query history, custom exact/regex rules, label-drop config, unused-metric detection, and Alloy remote_write fallback. Use when investigating a high Mimir/Grafana Cloud bill, hunting high-cardinality labels (`pod_uid`, `service_instance_id`, `version`), pre-aggregating counters/gauges, dropping unused metrics, or measuring `grafanacloud_instance_active_series` before/after — even when the user says "reduce cardinality", "too many series", "metrics spend", "active series count is exploding", or "drop the version label" without naming Adaptive Metrics.
---

# Grafana Cloud Adaptive Metrics

> **Docs**: https://grafana.com/docs/grafana-cloud/cost-management-and-billing/reduce-costs/metrics-costs/adaptive-metrics.md

Aggregation rules that pre-shrink high-cardinality metrics before storage — directly reduces active-series billing.

## Prerequisites

- Grafana Cloud Metrics plan (any paid tier)
- API key with `metrics:write` (for the Adaptive Metrics API — `adaptive-metrics.grafana.net`, Bearer auth)
- For the verification queries: the metrics query endpoint (`prometheus-prod-XX.grafana.net`) uses HTTP basic auth — `<metrics_user>` (numeric stack/instance ID) plus a token with `metrics:read` — not the Bearer key
- Access to **Home → Adaptive Metrics** in the Cloud portal

## Common Workflows

### 1. Review + apply auto-recommendations

```bash
# 1. Pull the recommendation list (sorted by series-reduction impact)
curl -s -H "Authorization: Bearer <KEY>" \
  "https://adaptive-metrics.grafana.net/api/v1/recommendations" \
  | jq '.recommendations[] | {metric_name, current_series, projected_series, estimated_reduction_percent}'

# 2. Capture the baseline series count for the target metric
#    (metrics query endpoint = basic auth, not the Bearer key)
curl -s -u "<metrics_user>:<metrics_token>" \
  "https://prometheus-prod-XX.grafana.net/api/prom/api/v1/query?query=count({__name__=\"process_cpu_seconds_total\"})" \
  | jq '.data.result[0].value[1]'   # → e.g. "12480"

# 3. Apply the recommendation (or click Apply in the UI)
curl -s -X POST -H "Authorization: Bearer <KEY>" \
  "https://adaptive-metrics.grafana.net/api/v1/recommendations/<ID>/apply"

# 4. Wait ~5 min. Verify — re-run the count query; expect a large drop.
#    Also check the saving metric:
#      grafanacloud_instance_active_series_dropped_by_aggregation_rules
```

**Rollback** — delete the rule:

```bash
curl -s -H "Authorization: Bearer <KEY>" \
  "https://adaptive-metrics.grafana.net/api/v1/rules" | jq '.rules[] | {id, metric_name}'
curl -s -X DELETE -H "Authorization: Bearer <KEY>" \
  "https://adaptive-metrics.grafana.net/api/v1/rules/<RULE_ID>"
# Or in the UI: Rules → row → Disable
```

### 2. Hand-write a custom rule

```bash
# 1. Sanity-check the metric is not used WITH that label in dashboards/alerts
grep -r 'process_cpu_seconds_total' dashboards/ alerts/ | grep -E 'version|go_version'
# Expect no hits → safe to drop.

# 2. Create the rule
curl -s -X POST -H "Authorization: Bearer <KEY>" -H "Content-Type: application/json" \
  "https://adaptive-metrics.grafana.net/api/v1/rules" \
  -d '{"rules":[{"metric_name":"process_cpu_seconds_total","match_type":"MATCH_TYPE_EXACT",
                 "drop_labels":["version","go_version"],
                 "aggregations":[{"type":"AGGREGATION_TYPE_SUM"}]}]}'

# 3. Verify — same count() query as above; series count should drop within 5 min.
```

Full payloads (regex match, aggregation types, all caveats): [`references/api.md`](references/api.md).

### 3. Drop unused metrics entirely

```bash
# 1. List unused metrics
curl -s -H "Authorization: Bearer <KEY>" \
  "https://adaptive-metrics.grafana.net/api/v1/usage-analysis?filter=unused" | \
  jq '.metrics[] | {metric_name, series_count, last_queried}'

# 2. Confirm not referenced in dashboards / alerts / recording rules
grep -r '<METRIC_NAME>' dashboards/ alerts/ recording-rules/

# 3. Add a write_relabel_config drop in Alloy (full block in references/api.md)
#    Reload Alloy: curl -X POST http://localhost:12345/-/reload

# 4. Verify — the metric should no longer appear in series counts after ~10 min
curl -s -u "<metrics_user>:<metrics_token>" \
  'https://prometheus-prod-XX.grafana.net/api/prom/api/v1/label/__name__/values' | jq '.data | index("<METRIC_NAME>")'  # → null
```

## Measure the impact

```promql
# Total active series (billed unit)
grafanacloud_instance_active_series

# Series specifically dropped by Adaptive Metrics rules
grafanacloud_instance_active_series_dropped_by_aggregation_rules
```

Rules take effect within ~5 minutes; full billing impact appears within an hour. The original high-cardinality samples keep flowing but the dropped labels no longer count toward billing.

## Resources

- [Adaptive Metrics docs](https://grafana.com/docs/grafana-cloud/cost-management-and-billing/reduce-costs/metrics-costs/adaptive-metrics/)
- [Adaptive Logs docs](https://grafana.com/docs/grafana-cloud/cost-management-and-billing/reduce-costs/logs-costs/adaptive-logs/)
- [Cardinality in Prometheus](https://grafana.com/docs/grafana-cloud/send-data/metrics/cardinality/)
