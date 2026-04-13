---
name: promql
license: Apache-2.0
description:
  Write, validate, and optimise PromQL queries for Prometheus and Grafana Cloud Metrics. Use when
  the user asks to query metrics, write a PromQL expression, calculate rates, aggregate across
  labels, build histogram quantiles, create recording rules, debug query performance, or
  understand metric cardinality. Triggers on phrases like "PromQL", "Prometheus query", "write a
  metric query", "calculate rate", "histogram_quantile", "recording rule", "metric cardinality",
  "sum by", "rate vs irate", "absent()", or "query is slow".
---

# PromQL Query Patterns

PromQL is a functional query language for time series data. Every query returns either an
**instant vector** (one value per label set at a point in time), a **range vector** (a sliding
window of samples), or a **scalar**.

**Golden rule:** `rate()` and `increase()` always require a range vector. The range must be at
least 4x the scrape interval to avoid gaps. For a 60s scrape interval, use `[5m]` minimum.

---

## Rate and counter queries

**Rate (per-second average over a window):**
```promql
rate(http_requests_total[5m])
```

**Rate with label aggregation — "sum then rate" is wrong, always rate then sum:**
```promql
# CORRECT: rate first, then aggregate
sum(rate(http_requests_total{job="api"}[5m])) by (status_code)

# WRONG: sum first destroys the counter monotonicity
sum(http_requests_total) by (status_code)   -- do NOT then rate() this
```

**Increase (total count over a window, not per-second):**
```promql
increase(http_requests_total[1h])
```

**irate vs rate:**
- `rate()` - smooth average over the full window. Use for dashboards and alerts.
- `irate()` - instantaneous rate from the last two samples. Use only when you need to capture
  spikes that `rate()` would average away. Never use for alerting.

---

## Filtering with label matchers

```promql
# Exact match
http_requests_total{job="api", status_code="200"}

# Regex match (anchored automatically)
http_requests_total{status_code=~"5.."}

# Negative regex
http_requests_total{status_code!~"2.."}

# Multiple values with regex OR
http_requests_total{env=~"staging|production"}
```

---

## Aggregation operators

Always aggregate after `rate()`:

```promql
# Sum across all instances, keep service label
sum(rate(http_requests_total[5m])) by (service)

# Average CPU per node, drop all other labels
avg(node_cpu_seconds_total{mode="idle"}) by (instance)

# 95th percentile request duration
histogram_quantile(0.95,
  sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service)
)

# Top 5 services by request rate
topk(5, sum(rate(http_requests_total[5m])) by (service))

# Count of distinct label values
count(count(up) by (job)) by ()
```

**`without` vs `by`:**
```promql
# Keep only the labels listed
sum(rate(http_requests_total[5m])) by (service, status_code)

# Drop only the labels listed, keep everything else
sum(rate(http_requests_total[5m])) without (instance, pod)
```

---

## Histogram quantiles

Native histograms (Prometheus 2.40+) and classic histograms use different syntax.

**Classic histogram (bucket metrics with `_bucket` suffix):**
```promql
histogram_quantile(0.99,
  sum(rate(http_request_duration_seconds_bucket{job="api"}[5m])) by (le)
)
```

**Multi-service comparison:**
```promql
histogram_quantile(0.95,
  sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service)
)
```

**Common mistake:** forgetting `by (le)` in the inner aggregation drops the bucket boundaries,
making `histogram_quantile` produce wrong results or NaN.

**Native histograms (simpler syntax):**
```promql
histogram_quantile(0.95, sum(rate(http_request_duration_seconds[5m])))
```

---

## Ratio and error rate

```promql
# Error ratio (errors / total)
sum(rate(http_requests_total{status_code=~"5.."}[5m]))
/
sum(rate(http_requests_total[5m]))

# Success rate as percentage
(1 -
  sum(rate(http_requests_total{status_code=~"5.."}[5m]))
  /
  sum(rate(http_requests_total[5m]))
) * 100

# Avoid division by zero with or vector(0)
sum(rate(errors_total[5m]))
/
(sum(rate(requests_total[5m])) > 0)
```

---

## Absence and staleness

```promql
# Alert when a metric disappears (e.g. a job stops reporting)
absent(up{job="api"})

# Alert when a metric value hasn't changed (potential stale exporter)
changes(up{job="api"}[5m]) == 0

# Check if a metric has been present in the last window
count_over_time(up{job="api"}[5m]) > 0
```

---

## Time functions and offsets

```promql
# Compare current value to 1 hour ago
rate(http_requests_total[5m])
-
rate(http_requests_total[5m] offset 1h)

# Day-over-day comparison
rate(http_requests_total[5m])
/
rate(http_requests_total[5m] offset 1d)

# Predict value in 2 hours based on current trend (linear regression)
predict_linear(node_filesystem_avail_bytes[1h], 2 * 3600)
```

---

## Recording rules

Recording rules pre-compute expensive queries, improving dashboard load time and reducing
Prometheus query load. Store them in a rules file loaded by Prometheus or Grafana Mimir.

```yaml
groups:
  - name: http_request_rates
    interval: 1m
    rules:
      # Pre-compute per-service request rate
      - record: job:http_requests_total:rate5m
        expr: |
          sum(rate(http_requests_total[5m])) by (job)

      # Pre-compute error ratio per service
      - record: job:http_errors:ratio5m
        expr: |
          sum(rate(http_requests_total{status_code=~"5.."}[5m])) by (job)
          /
          sum(rate(http_requests_total[5m])) by (job)

      # Pre-compute p95 latency per service (avoids expensive histogram_quantile on dashboards)
      - record: job:http_request_duration_p95:rate5m
        expr: |
          histogram_quantile(0.95,
            sum(rate(http_request_duration_seconds_bucket[5m])) by (le, job)
          )
```

**Naming convention:** `<aggregation_level>:<metric_name>:<operation_and_window>`

---

## SLO queries

```promql
# Availability SLO: fraction of successful requests over 30 days
1 - (
  sum(increase(http_requests_total{status_code=~"5.."}[30d]))
  /
  sum(increase(http_requests_total[30d]))
)

# Error budget burn rate (1h window, alerting when burning > 14.4x the allowed rate)
(
  sum(rate(http_requests_total{status_code=~"5.."}[1h]))
  /
  sum(rate(http_requests_total[1h]))
)
/
(1 - 0.999)   -- replace 0.999 with your SLO target
```

---

## Cardinality and performance

High cardinality label values (UUIDs, user IDs, URLs) make queries slow and storage expensive.

```promql
# Find metrics with the most label combinations (run in Grafana Explore)
topk(10, count by (__name__)({__name__=~".+"}))

# Find series count for a specific metric
count(http_requests_total)

# Check label value cardinality
count(count by (user_id)(http_requests_total))
```

**Rules for controllable cardinality:**
- Never put high-cardinality values (request IDs, user IDs, email addresses) in label values
- Group URLs into route patterns: `/api/users/123` → `/api/users/{id}`
- Use `relabel_configs` to drop labels before ingestion

```yaml
# Drop a high-cardinality label during scrape (in Alloy or Prometheus scrape config)
prometheus.scrape "api" {
  targets = [...]
  rule {
    source_labels = ["user_id"]
    action        = "labeldrop"
  }
}
```

---

## Common patterns

**Service availability (for use in alert rules):**
```promql
avg_over_time(up{job="api"}[5m]) < 0.9
```

**Saturation (resource near-full):**
```promql
# Disk filling up (predict full in < 4h based on 1h trend)
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[1h], 4 * 3600) < 0
```

**Throughput spike:**
```promql
# Current rate > 3x the 1-hour average
rate(http_requests_total[5m])
>
3 * avg_over_time(rate(http_requests_total[5m])[1h:5m])
```

---

## References

- [Prometheus querying basics](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Explore — PromQL](https://grafana.com/docs/grafana/latest/explore/)
- [Prometheus best practices](https://prometheus.io/docs/practices/naming/)
- [Grafana Cloud Metrics (Grafana Mimir)](https://grafana.com/docs/mimir/latest/)
