# Final report template

Fill in this template at the end of the engagement. Hand the
filled-in report to the user as the final artefact.

Be specific. Every claim cites evidence. No hand-wavy summaries.

---

## Report template

```markdown
# Performance test report — <site>

**Date**: <YYYY-MM-DD>
**Target**: <https://example.com>
**Tester**: <agent or human name>

## Summary

- **Workflows tested**: wN-<short-name>, …
- **Test types run**:
  - smoke    — local ✓ / cloud N/A
  - average  — local ✓ / cloud ✓
  - stress   — local ✓ / cloud ✓
  - spike    — local ✓ / cloud N/A
  - soak     — local ✓ / cloud N/A
  - breakpoint — local ✓ / cloud ✓
- **Backend investigated**: yes (Grafana access via <url>) / no
- **Outcome**: <pass / pass-with-findings / fail>

## SLOs and threshold results

| SLO                                              | Result    | Notes                |
|--------------------------------------------------|-----------|----------------------|
| http_req_failed rate < 0.01                      | PASS / FAIL | <window or n/a>    |
| http_req_duration p(95) < 500ms                  | PASS / FAIL | <window or n/a>    |
| http_req_duration{name:CreateOrder} p(95) < 800ms| PASS / FAIL | failed at <window> |
| iteration_duration{scenario:browser} p(95) < 10s | PASS / FAIL |                    |
| browser_web_vital_lcp p(95) < 2500ms             | PASS / FAIL |                    |
| browser_web_vital_inp p(95) < 200ms              | PASS / FAIL |                    |
| browser_web_vital_cls p(95) < 0.1                | PASS / FAIL | loosened to <0.2 for W1 — see Finding N |
| iteration_completed{scenario:browser} rate > 0.99| PASS / FAIL |                    |

## Findings

Ordered by severity. Each finding has: observation, evidence,
suggested next step (neutral — for the user's team to evaluate).

### Finding 1 — <one-line summary>

**Severity**: critical / high / medium / low / informational

**Observation**:

  During the stress test of W3 (started 2026-05-13 22:14 UTC, ended
  22:30 UTC), the `GetRecommendation` endpoint's p(95) latency rose
  from 120ms at baseline to 1.4s at peak load (50 VUs). The
  threshold `http_req_duration{name:GetRecommendation} p(95) <
  1000ms` failed.

**Evidence**:

  - k6 summary: `/tmp/perf-lg-monitor/w3-anon-recommend-stress-20260513-221400.k6.log`
  - LG monitor: `/tmp/perf-lg-monitor/w3-anon-recommend-stress-20260513-221400.csv`
    (sys_cpu_idle stayed ≥ 51% throughout — LG was not the
    bottleneck)
  - Grafana panel: <link> showing backend latency in the same
    window
  - Pyroscope: <link> showing <top frame> consumed 53% of CPU
    samples

**Suggested next step**:

  Customer engineers should investigate whether the
  `<top frame from Pyroscope>` code path can be optimised or
  moved off the hot loop. Without that, the system will not
  meet the GetRecommendation SLO above ~40 concurrent users.

### Finding 2 — …

(repeat the structure)

## Loosened or skipped thresholds

If you raised any threshold from the default, list each here with
the cause. Never silently loosen.

| Threshold                            | Original | Loosened to | Cause                                  |
|--------------------------------------|----------|-------------|----------------------------------------|
| browser_web_vital_cls{workflow:w1}   | < 0.1    | < 0.2       | Deterministic CLS=0.15 in ratings widget; team accepted, will not fix in test window |

## Evidence index

All file paths and Grafana URLs referenced in findings.

### k6 outputs
- `/tmp/perf-lg-monitor/w1-*-{smoke,average,stress,spike,soak}-*.k6.log`
- `/tmp/perf-lg-monitor/w2-*-{smoke,average,stress,spike,soak}-*.k6.log`
- …

### LG monitor CSVs
- `/tmp/perf-lg-monitor/*.csv`

### Cloud k6 runs
- <Grafana Cloud k6 URL> — w3 stress, 2026-05-13
- <Grafana Cloud k6 URL> — w3 breakpoint, 2026-05-13

### Grafana investigation
- Datasource UIDs used: prom=<uid>, loki=<uid>, tempo=<uid>, pyroscope=<uid>
- Service labels: `service_name="<value>"`
- Run windows correlated:
  - w3 stress: 2026-05-13 22:14-22:30 UTC
  - w3 breakpoint: 2026-05-13 23:01-23:21 UTC

## Methodology notes

- Test suite committed at: <repo / path>
- k6 version: <e.g. v2.0.1>
- Node.js version: <e.g. 23.0.0>
- LG host: <hostname / spec — e.g. MacBook Pro M2 Max, 32GB>
- LG sidecar interval: 5s (default)
- Hybrid scenario shape: 1 protocol scenario + 1 browser VU
  (except breakpoint, protocol-only)
- Threshold strategy: global SLO + per-endpoint tags + per-iteration
  + LCP/INP/CLS Web Vitals + custom action Trend
  (see <skill reference>)

## Suggested next steps (overall)

- Address Findings 1-N in priority order.
- Re-run stress and breakpoint after each fix to measure
  improvement.
- Consider adding the SLO thresholds in this report to your CI
  pipeline using `k6 run --threshold=...` so regressions surface
  before deploy.
- Schedule a quarterly re-run to detect drift.
```

---

## Writing rules

### Be specific

- "Latency increased" → ❌
- "GetRecommendation p(95) rose from 120ms to 1.4s between 22:14
  and 22:24 UTC" → ✓

### Cite evidence

Every numeric claim has a file path or URL. If you can't cite it,
don't claim it.

### Stay neutral

The skill **reports**, doesn't **recommend code**. "Customer should
fix X by doing Y" — never. "Customer should investigate whether X
can be optimised" — yes.

### Don't fabricate

If backend access was not available, the "Backend investigated"
flag is `no` and there are no Pyroscope / Tempo evidence cites.
Don't paper over the gap with client-side speculation.

### Severity guide

- **critical**: SLO failed, user-facing impact, blocker for
  production.
- **high**: SLO failed, scope-limited to a specific workflow.
- **medium**: threshold trending toward fail; near the cliff.
- **low**: cosmetic or rare-edge-case behaviour.
- **informational**: observation, not a problem.

When in doubt, use a lower severity. Inflating severity erodes
the report's credibility.
