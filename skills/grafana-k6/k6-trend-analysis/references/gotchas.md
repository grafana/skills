# Gotchas

| Issue | Detail |
|-------|--------|
| **Zero-observation thresholds** | A threshold with zero observations passes by default in k6. If a metric appears to pass but has no data, flag it -- the threshold is not actually being evaluated. |
| **Metric type changes across runs** | If a metric's type changed between runs (e.g., script refactor), the multi-run aggregate endpoint uses the latest type. Earlier runs queried with the wrong method return empty. Flag this if detected. |
| **Incomplete runs skew trends** | Aborted or timed-out runs typically have shorter durations and fewer iterations, producing unrepresentative metric values. Exclude them by default. |
| **LG resource metrics** | `load_generator_cpu_percent` and `load_generator_file_handles` trending up may indicate the test is outgrowing its load generator allocation, not that the service is degrading. Call this out separately. |
| **Rate metric direction** | For `ratio`-type rate metrics (like check pass rates), "degrading" means the value is *decreasing* (fewer passes), which is the opposite direction from latency metrics. |
