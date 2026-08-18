# Report template

Use this structure. Omit sections that don't apply (e.g., skip "Anomalies" if
none were detected).

```markdown
# Trend Analysis: {test_name}

**Test ID**: {test_id}
**Analysis window**: {start_date} to {end_date} ({N} runs analyzed)
**Overall health**: {Healthy | Watch | Degrading | Critical}

## Run Summary

| Period | Runs | Passed | Failed | Pass Rate |
|--------|------|--------|--------|-----------|
| First half | N | N | N | N% |
| Second half | N | N | N | N% |

## Metric Trends

| Metric | Type | Current | Baseline | Change | Trend | Threshold | Headroom |
|--------|------|---------|----------|--------|-------|-----------|----------|
| http_req_duration (P95) | trend | 380ms | 250ms | +52% | Degrading | 500ms | 24% |
| http_req_failed | rate | 0.8% | 0.3% | +167% | Degrading | 1% | 20% |
| http_reqs | counter | 15,230 | 15,100 | +0.9% | Stable | - | - |

## Flagged Issues

### 1. {metric_name}: {classification}
- **Current**: {value} | **Baseline**: {value} | **Change**: {pct}%
- **Threshold**: {threshold} | **Headroom**: {pct}%
- **Rate of change**: {pct}% per week
- **Projected breach**: ~{N} weeks at current rate
- **Anomalous runs**: {run_ids with dates, if any}

## Threshold Recommendations

| Metric | Current Threshold | Recommended | Rationale |
|--------|-------------------|-------------|-----------|
| http_req_duration | p(95)<500 | p(95)<420 | Current P95 is 380ms; tightening to 420ms gives 10% headroom from current performance while surfacing further degradation early |

## Suggested Next Steps

- [ ] **Investigate service side**: P95 latency has increased 52% -- consider
      loading `debug-with-grafana` to check service health
- [ ] **Deep-dive run {run_id}**: anomalous P95 spike on {date} -- consider
      loading `k6-cloud-investigate-test` for this run
- [ ] **Tighten thresholds**: 2 metrics have >30% headroom that could be
      tightened -- consider loading `k6-test-maintenance` to apply changes
```

## Overall health classification

Derive the overall health from the worst-case metric:
- **Healthy**: all metrics stable or improving, headroom comfortable or adequate
- **Watch**: at least one metric degrading but headroom still adequate
- **Degrading**: at least one metric degrading with thin headroom
- **Critical**: at least one metric has breached its threshold, or multiple
  metrics are degrading with thin headroom
