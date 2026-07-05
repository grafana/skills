---
name: cost-management
license: Apache-2.0
description: Cut your Grafana Cloud bill by attributing spend to teams and reducing telemetry volume. Covers FOCUS-compliant billing dashboards, cost-attribution labels in Alloy, Adaptive Metrics (cardinality reduction), Adaptive Logs (drop/sample), Adaptive Traces (tail sampling), usage alerts, and an optimization checklist. Use when investigating a high Grafana Cloud bill, attributing observability cost to a team or service, reducing active series / log bytes / trace spans, or setting up usage / quota alerts — even when the user says "our Grafana bill is too high", "who's burning the most metrics", "drop debug logs", "sample our traces", or "alert me before we hit quota" without naming Cost Management.
---

# Grafana Cloud Cost Management

> **Docs**: https://grafana.com/docs/grafana-cloud/cost-management-and-billing/

Reduce metric / log / trace spend with Adaptive signals + cost-attribution labels.

## Prerequisites

- A Grafana Cloud stack with Adaptive Metrics / Logs / Traces enabled (visible under **Cost Management**)
- Alloy (or Grafana Agent) ingesting telemetry, with API key in scope `metrics:write` + `logs:write` (+ `traces:write`)
- Admin access to the stack to apply Adaptive recommendations

## Common Workflows

### 1. Attribute cost to a team / service

```alloy
# 1. Add external labels in Alloy (metrics + logs configs)
prometheus.remote_write "cloud" {
  endpoint { url = sys.env("PROMETHEUS_URL") /* ... */ }
  external_labels = { team = "platform", project = "checkout-service" }
}
```

```bash
# 2. Reload Alloy
curl -X POST http://localhost:12345/-/reload

# 3. Verify labels arrived in Grafana Cloud
#    In Explore, run:  count by (team, project) ({__name__=~".+"})
#    Then visit Cost Management → group by `team` / `project`
```

See [`references/adaptive-signals.md`](references/adaptive-signals.md) for the full Alloy snippet.

### 2. Cut metric cardinality with Adaptive Metrics

```bash
# 1. Pull recommendations
curl https://<stack>.grafana.net/api/plugins/grafana-adaptive-metrics-app/resources/v1/recommendations \
  -H "Authorization: Bearer <token>" | jq '.recommendations | length'

# 2. In the UI: Grafana Cloud → Adaptive Metrics → review rules sorted by series-reduction impact
# 3. Test in "Preview" mode before applying
# 4. Apply (takes effect within 5 min)

# 5. Verify — series count should drop on the affected metrics
#    Before applying, capture baseline:
#      count({__name__="http_request_duration_seconds_bucket"})
#    Wait 10 min after apply, run again — expect 10x+ reduction for high-card metrics.

# Rollback if needed: open the rule in the UI → Disable, or DELETE /v1/rules/<id>.
```

### 3. Drop noisy logs in Alloy

```alloy
# 1. Add a filter stage (see references/adaptive-signals.md for the full block)
loki.process "filter_logs" {
  forward_to = [loki.write.cloud.receiver]
  stage.drop { expression = ".*GET /health.*" }
}
```

```bash
# 2. Reload Alloy
curl -X POST http://localhost:12345/-/reload

# 3. Verify the filter — health logs should NOT appear in Logs Drilldown
#    LogQL check (should return 0):
#      sum(rate({app="my-app"} |= "GET /health" [5m]))
#    Bytes-ingested should also drop. Compare 24h before/after:
#      sum(increase(loki_ingester_chunk_size_bytes_sum[24h])) by (namespace)
```

### 4. Set a usage alert before you hit quota

See [`references/alerts-and-queries.md`](references/alerts-and-queries.md) for ready-to-paste rules (`MetricsUsageHigh`, `LogsIngestionHigh`).

## Optimization checklist

- [ ] Apply Adaptive Metrics recommendations — typically reduces series 40-60%
- [ ] Drop health/readiness probe logs in Alloy
- [ ] Tail-sample traces to 5-10% + keep errors / slow spans
- [ ] Add `team` + `project` external labels to every Alloy config
- [ ] Set usage alerts at 80% of quota
- [ ] Replace expensive ad-hoc queries with recording rules

## References

- [`references/adaptive-signals.md`](references/adaptive-signals.md) — Adaptive Metrics / Logs / Traces config; cost-attribution labels
- [`references/alerts-and-queries.md`](references/alerts-and-queries.md) — usage alert rules, cost-finding PromQL, billing-unit table

## Resources

- [Cost Management docs](https://grafana.com/docs/grafana-cloud/cost-management-and-billing/)
- [Adaptive Metrics](https://grafana.com/docs/grafana-cloud/cost-management-and-billing/reduce-costs/metrics-costs/adaptive-metrics/)
- [Adaptive Logs](https://grafana.com/docs/grafana-cloud/cost-management-and-billing/reduce-costs/logs-costs/)
