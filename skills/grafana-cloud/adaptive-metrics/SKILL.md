---
name: adaptive-metrics
license: Apache-2.0
description:
  Reduce Grafana Cloud Metrics costs by managing cardinality with Adaptive Metrics aggregation
  rules. Use when the user asks to reduce metrics costs, manage cardinality, create aggregation
  rules, apply label dropping, analyse unused metrics, understand Active Series, or optimise
  Prometheus storage. Triggers on phrases like "adaptive metrics", "reduce cardinality",
  "aggregation rules", "metrics cost", "too many series", "Active Series", "label dropping",
  "unused metrics", "cardinality reduction", or "metrics spend".
---

# Grafana Cloud Adaptive Metrics

Adaptive Metrics analyses your Prometheus metrics usage and suggests aggregation rules that
reduce series count without breaking any queries. Rules pre-aggregate high-cardinality metrics
into lower-cardinality forms before storage.

**How it works:**
1. Adaptive Metrics scans your metric usage (dashboards, alerts, recording rules) over a lookback window
2. It identifies labels that are never queried for a given metric
3. It generates aggregation rules that drop those labels, reducing series count
4. The original high-cardinality metric is still ingested but the aggregated form is what gets stored long-term

**Billing:** Grafana Cloud charges per Active Series (series that received a sample in the last hour).
Adaptive Metrics reduces your Active Series count, directly reducing your bill.

---

## Step 1: Access Adaptive Metrics

In Grafana Cloud: **Home > Adaptive Metrics** (or via the app menu).

You need the Grafana Cloud Metrics plan. Adaptive Metrics is available on all paid plans.

**Key views:**
- **Overview** - total series count, estimated savings from pending recommendations
- **Recommendations** - auto-generated aggregation rules ready to apply
- **Rules** - active rules and their effect
- **Usage analysis** - which metrics are queried vs. unused

---

## Step 2: Understand the recommendations

Recommendations are sorted by estimated series reduction (highest savings first).

Each recommendation shows:
- **Metric name** - the metric being aggregated
- **Current series** - series count before the rule
- **Projected series** - series count after applying the rule
- **Labels to drop** - labels that are never queried for this metric
- **Labels to keep** - labels that appear in at least one query
- **Lookback period** - how many days of query history was analysed

**Review before applying:**

```bash
# Check if any dashboards or alerts use the label being dropped
# Replace METRIC_NAME and LABEL_NAME with actual values
grep -r "METRIC_NAME" /path/to/dashboards/ --include="*.json" | grep "LABEL_NAME"
```

Or in Grafana: use **Explore > Metrics** to query the metric and check which labels are present
and used.

---

## Step 3: Apply a recommendation

**Via the UI:**
1. Go to Adaptive Metrics > Recommendations
2. Review the recommended labels to keep/drop
3. Click **Apply** on rules you want to enable
4. Rules take effect within ~5 minutes

**Via the API:**

```bash
# List recommendations
curl -s -H "Authorization: Bearer <API_KEY>" \
  "https://adaptive-metrics.grafana.net/api/v1/recommendations" | \
  jq '.recommendations[] | {metric_name, current_series, projected_series, estimated_reduction_percent}'

# Apply a recommendation by ID
curl -s -X POST \
  -H "Authorization: Bearer <API_KEY>" \
  -H "Content-Type: application/json" \
  "https://adaptive-metrics.grafana.net/api/v1/recommendations/<RECOMMENDATION_ID>/apply"
```

---

## Step 4: Create custom aggregation rules

If you know which labels to drop without waiting for recommendations, create rules directly.

**Rule format:**

```yaml
# Aggregation rule: keep only job and instance labels for process_cpu_seconds_total
rules:
  - match_metric: process_cpu_seconds_total
    drop_labels:
      - version
      - go_version
      - service_name
    aggregations:
      - type: sum
        without: []   # empty = keep only the labels not in drop_labels
```

**Via the API:**

```bash
curl -s -X POST \
  -H "Authorization: Bearer <API_KEY>" \
  -H "Content-Type: application/json" \
  "https://adaptive-metrics.grafana.net/api/v1/rules" \
  -d '{
    "rules": [
      {
        "metric_name": "process_cpu_seconds_total",
        "match_type": "MATCH_TYPE_EXACT",
        "drop_labels": ["version", "go_version"],
        "aggregations": [{"type": "AGGREGATION_TYPE_SUM"}]
      }
    ]
  }'
```

**Aggregation types:**

| Type | Use case |
|---|---|
| `sum` | Counters, request counts, byte totals |
| `max` | Gauges where you want the worst-case (e.g. CPU max across pods) |
| `min` | Gauges where you want the best-case |
| `avg` | Rate metrics, averages |

**For counters, always use `sum`.** Averaging counters produces incorrect rates.

---

## Step 5: Handle metrics with regex matching

Use regex rules to cover families of metrics with similar label patterns:

```bash
# Apply a rule to all metrics matching a pattern
curl -s -X POST \
  -H "Authorization: Bearer <API_KEY>" \
  -H "Content-Type: application/json" \
  "https://adaptive-metrics.grafana.net/api/v1/rules" \
  -d '{
    "rules": [
      {
        "metric_name": "go_.*",
        "match_type": "MATCH_TYPE_REGEX",
        "drop_labels": ["go_version", "version", "service_instance_id"],
        "aggregations": [{"type": "AGGREGATION_TYPE_SUM"}]
      }
    ]
  }'
```

**Common label families safe to drop globally:**
- `version`, `app_version`, `go_version` - rarely queried in PromQL
- `service_instance_id`, `pod_uid`, `container_id` - ultra-high cardinality
- `git_commit`, `build_date` - static labels that inflate series for no query value

---

## Step 6: Identify unused metrics

Unused metrics (never queried in any dashboard, alert, or recording rule) can be dropped entirely.

**In the UI:** Adaptive Metrics > Usage analysis > "Unused metrics" tab

**Via the API:**

```bash
curl -s -H "Authorization: Bearer <API_KEY>" \
  "https://adaptive-metrics.grafana.net/api/v1/usage-analysis?filter=unused" | \
  jq '.metrics[] | {metric_name, series_count, last_queried}'
```

**Before dropping a metric entirely:**
1. Confirm it is not used in any Grafana dashboard (search by metric name in dashboard JSON)
2. Confirm it is not used in any Prometheus/Mimir alert rule or recording rule
3. Check with the team that owns the service if the metric is part of an SLO

**Drop unused metrics via remote_write filtering in Alloy:**

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

---

## Step 7: Adaptive Logs (companion product)

For log volume reduction, Adaptive Logs works the same way for Loki:

```bash
# Check log volume recommendations
curl -s -H "Authorization: Bearer <API_KEY>" \
  "https://adaptive-logs.grafana.net/api/v1/recommendations" | \
  jq '.recommendations[] | {stream_selector, estimated_reduction_percent}'
```

Log pattern: drops low-value log streams (e.g. debug logs from non-critical services) during
high-volume periods or permanently.

---

## Step 8: Measure the impact

After applying rules, monitor the effect over 24-48 hours:

```promql
# Active Series count over time (visible in Grafana Cloud Metrics Usage dashboard)
grafanacloud_instance_active_series

# Series reduction from adaptive metrics
grafanacloud_instance_active_series_dropped_by_aggregation_rules
```

In Grafana Cloud: **Home > Usage > Metrics** shows before/after series counts and the billing
impact of active rules.

**Expected timeline:**
- Rules take effect within ~5 minutes of creation
- Full billing impact visible after the next billing cycle (usually within 1 hour)
- The original high-cardinality metric continues to be ingested but doesn't count toward billing
  for the labels that were dropped

---

## References

- [Adaptive Metrics documentation](https://grafana.com/docs/grafana-cloud/cost-management-and-billing/reduce-costs/metrics-costs/adaptive-metrics/)
- [Adaptive Logs documentation](https://grafana.com/docs/grafana-cloud/cost-management-and-billing/reduce-costs/logs-costs/adaptive-logs/)
- [Cardinality management in Prometheus](https://grafana.com/docs/grafana-cloud/send-data/metrics/cardinality/)
- [Grafana Cloud pricing](https://grafana.com/pricing/)
