---
name: k6-trend-analysis
description: >
  Analyze Grafana Cloud k6 test run trends over time. Detects slow metric drift
  (e.g., P95 latency creeping up while still passing thresholds), computes
  headroom to thresholds, flags anomalies, and recommends threshold tightening.
  Use when the user asks about test performance trends, wants to know if metrics
  are degrading, asks whether thresholds should be tightened, or wants a health
  check across recent runs for a specific test. Trigger on phrases like "how is
  my test trending", "is P95 getting worse", "check for performance regression",
  "should I tighten thresholds", "are my tests degrading", "show me trends for
  test X", "analyze my k6 test runs", or "is my test getting slower". Also
  trigger when a user asks to check all tests in a project -- run this skill
  once per test and synthesize.
---

# k6 Trend Analysis

Analyze metric trends across multiple runs of a Grafana Cloud k6 test to catch
degradation early -- before thresholds breach and alerts fire. A P95 at 380ms
against a 500ms threshold is "green" today, but if it was 250ms a month ago,
something is quietly degrading; this skill surfaces that drift and recommends action.

## Scope & dependencies

Detection and recommendations only -- hand off:
- single-run failure deep-dive -> `k6-cloud-investigate-test`
- script / threshold edits -> `k6-test-maintenance`
- new test creation -> the test-creation workflow
- service-side metric queries -> `debug-with-grafana`

All GCk6 API mechanics (auth, the doubled `cloud/cloud/` path prefix, `@nextLink`
pagination, the spill envelope, metric query syntax) are delegated to **`k6-manage`**,
driven via **`gcx`** -- read it before any API call; don't duplicate it here.

---

## Workflow

Follow these steps in order. Present findings at the end -- do not apply changes.

### Step 1: Identify the test

The user provides one of:
- A GCk6 URL (extract the load test ID from the path)
- A test ID directly
- A test name (search via `gcx k6 tests list` or the v6 API)

Confirm the test exists by fetching its metadata. Record the `id`, `name`,
`project_id`, and `created` timestamp. You will need the load test ID (not a
run ID) for the multi-run metric endpoints.

### Step 2: Determine the analysis window

Default to **last 30 days**. Adjust if:
- The user requests a specific window
- The test has very few runs (<5 in 30 days) -- widen the window and note this
- The test runs very frequently (hundreds of runs in 30 days) -- consider
  sampling or narrowing. Ask the user if the volume is extreme (>200 runs)

State the window explicitly: "Analyzing runs from {start_date} to {end_date}."

### Step 3: Fetch runs in the window

List all runs for the test using the v6 API with `$orderby=created desc`
pagination (see k6-manage Section 3 for the `@nextLink` loop pattern). Filter
to runs within the analysis window.

For each run, record:
- `id`, `created`, `ended`
- `result` (passed/failed/timed_out)
- `status` (created/queued/initializing/running/finished/aborted)
- `note` (if present -- users sometimes annotate runs)

Discard runs that did not reach `finished` status (aborted, timed_out, etc.)
unless the user specifically asks about them -- incomplete runs produce
unreliable metric aggregates.

Count the runs. If fewer than 3 usable runs exist, inform the user that trend
analysis is not meaningful with this sample size and suggest widening the window
or waiting for more runs.

### Step 4: Fetch all metrics and their types

Before querying values, discover what metrics the test emits. Use the multi-run
metric listing endpoint (k6-manage references/metrics.md Section 2):

```
GET /cloud/v5/load_tests/{loadTestId}/metrics(test_run_ids=[{id1},{id2},...])
```

Pass a representative subset of run IDs (the first and last few) to catch
metrics that may have been added or removed over the window. Record each
metric's `name` and `type` (counter, gauge, trend, rate).

Group metrics by type -- the query method must match the metric type (see
metrics.md "Query methods"). Using the wrong method returns empty results.

### Step 5: Fetch per-run aggregate values

For each metric, query its aggregate value across all runs in the window using
the multi-run aggregate endpoint (metrics.md Section 8):

```
GET /cloud/v5/load_tests/{loadTestId}/query_aggregate_k6(
  query='<method>',
  metric='<metric_name>',
  test_run_ids=[{id1},{id2},...]
)
```

Concrete `gcx` form (proxy prefix per k6-manage §2; `-o json` avoids the spill envelope):

```bash
LT=<load_test_id>; IDS="123,124,125"
gcx --context <ctx> api "/api/plugins/k6-app/resources/cloud/cloud/v5/load_tests/$LT/query_aggregate_k6(query='histogram_quantile(0.95)',metric='http_req_duration',test_run_ids=[$IDS])" -o json
```

Choose the aggregate method based on metric type:

| Metric type | Primary method | What it captures |
|-------------|---------------|------------------|
| **trend** | `histogram_quantile(0.95)` | P95 latency -- the most common SLO target |
| **trend** | `histogram_quantile(0.5)` | Median -- shows typical behavior |
| **trend** | `histogram_avg` | Mean -- sensitive to outliers |
| **counter** | `increase` | Total count per run |
| **rate** | `ratio` | Success/failure ratio |
| **gauge** | `max` | Peak value per run |

For trend-type metrics (latencies), query multiple quantiles (P50, P90, P95,
P99) to see if degradation is uniform or concentrated in the tail.

**Always break down by request grouping for multi-target tests.** A single
aggregate p95 across a whole test obscures regressions confined to one
endpoint or one page -- a 3x slowdown on one URL can be invisible at the
test-level p95 if the test hits many URLs. Default to grouped queries:

| Metric pattern | Default grouping | Why |
|----------------|------------------|-----|
| `browser_web_vital_*` (LCP, FCP, CLS, TTFB, INP, FID) | `by (url)` | Each navigation emits its own web vital; per-URL trends pin regressions to a specific page. |
| `http_req_duration`, `http_req_failed`, `http_reqs` | `by (name, status)` if requests are tagged with `name`; otherwise `by (url, status)` | Different endpoints have different baselines; mixing them hides per-endpoint drift. |
| `iteration_duration` (multi-scenario tests) | `by (scenario)` | Browser and protocol scenarios have very different durations; mixing them is meaningless. |
| Custom trends with tags | `by (<the tag>)` | Whatever the user tagged on is presumably what they care about. |

Discover available labels first via the labels endpoint (metrics.md §4) and
label-values endpoint (metrics.md §5) before constructing the grouped query.
Don't assume labels from reading the script -- a tag rename or refactor can
silently shift the label space. Example:

```
# List labels for a specific metric on a representative run
GET /cloud/v5/test_runs/{id}/labels?match[]=browser_web_vital_lcp

# Then enumerate values for a useful label
GET /cloud/v5/test_runs/{id}/label/url/values
```

Only fall back to the bare aggregate (no `by`) for metrics where grouping
adds no information -- e.g., `vus`, `load_generator_cpu_percent`,
single-target tests where every request hits the same URL.

The response includes `test_run_id` as a label -- use this to map each value
back to its run timestamp from Step 3. Grouped queries return one series per
(group, run) combination; flatten into a tidy "rid x group" table for the
trend computation in Step 7.

If there are too many run IDs to fit in a single URL (hundreds), batch the
queries into groups of 50 run IDs and merge the results.

### Step 6: Extract thresholds

Thresholds define what "passing" means. Fetch the test's current script (via
k6-manage Section 5) and parse the `export const options = { thresholds: {...} }`
block. Record each threshold's:
- Metric name and selector (e.g., `http_req_duration{name:homepage}`)
- Condition (e.g., `p(95)<500`)
- Whether `abortOnFail` is set

Also check the most recent run's threshold results from the run data to see
which thresholds are currently passing vs. failing.

Not all metrics will have thresholds -- that's fine. Metrics without thresholds
still get trend analysis; they just won't have headroom calculations.

### Step 7: Compute trends

**Detect inflection points and rule out script changes deterministically.**
Before drawing conclusions about a regression, look for discontinuities in
the metric values -- sudden jumps or drops that align across multiple
metrics on the same date. When you spot one, do not guess whether the
script changed. The run-bundled script endpoint gives a deterministic
answer in seconds:

1. **sha256-diff the bundled scripts at the boundary.** Fetch the snapshot
   from the last "before" run and the first "after" run via
   `GET /cloud/v6/test_runs/{id}/script` (k6-manage §5, "Two distinct
   script endpoints" -- use the run-scoped endpoint, not the load-test
   one, since the latter only shows the current version). Compare with
   `shasum -a 256`.

   ```bash
   gcx --context <ctx> api /api/plugins/k6-app/resources/cloud/cloud/v6/test_runs/<before_id>/script > /tmp/before.bin
   gcx --context <ctx> api /api/plugins/k6-app/resources/cloud/cloud/v6/test_runs/<after_id>/script > /tmp/after.bin
   shasum -a 256 /tmp/before.bin /tmp/after.bin
   ```

   For thoroughness on multi-run inflections, hash every run across the
   transition -- if N consecutive runs share one hash and N more share
   another, you have a clean before/after boundary. If hashes change
   mid-stream, the test was edited multiple times.

2. **If the sha256 differs**, the test script changed -- the inflection
   may be a test-side artifact, not a service regression. Split the
   analysis into distinct eras at the boundary and compute trends within
   each era separately. Comparing metrics across script changes produces
   misleading trends -- a P95 drop from 3,000ms to 150ms is not an
   "improvement" if the script simply stopped hitting a slow endpoint.
   State the eras explicitly in the report and focus recommendations on
   the most recent era.

3. **If the sha256 matches**, the script is byte-identical and the
   regression is external to the test (service-side, infrastructure, or
   load-zone). This is high-confidence information -- carry it into Step 9
   (service-side correlation) instead of leaving "did the test change?"
   as an open question.

This sha256 diff is a 5-second deterministic check that rules out a huge
class of causes. Run it at every detected inflection, not just when the
user asks.

For each metric, build a time-ordered series of (run_timestamp, value) pairs.
Then compute:

**Basic statistics:**
- Mean, standard deviation, min, max across all runs
- Current value (most recent run)
- Baseline value (oldest run in window, or mean of first 3 runs for stability)

**Trend direction:**
Split the runs into two halves (first half and second half of the time window).
Compare the mean of each half:
- **Degrading**: second-half mean is worse by >10% (higher for latency/errors,
  lower for success rates)
- **Improving**: second-half mean is better by >10%
- **Stable**: change is within 10%
- **Volatile**: standard deviation exceeds 25% of the mean, regardless of
  direction

The 10% and 25% thresholds are starting points. If the user's test has very
tight tolerances or very noisy metrics, adjust and explain the reasoning.

**Rate of change:**
Express as percentage change per week: `((recent_mean - baseline_mean) / baseline_mean) * 100 / weeks_in_window`. This normalizes across different window sizes.

**Anomaly detection:**
Flag any run where the metric value is more than 2 standard deviations from the
overall mean. These are potential inflection points worth investigating
individually.

### Step 8: Headroom analysis

For metrics that have thresholds defined (from Step 6), compute headroom:

```
headroom_pct = ((threshold_value - current_value) / threshold_value) * 100
```

Classify headroom:
- **Comfortable** (>50%): well within limits
- **Adequate** (20-50%): healthy but worth monitoring
- **Thin** (<20%): at risk of breaching if trends continue
- **Breached** (<0%): already failing

For degrading metrics with thin headroom, estimate when the threshold will be
breached if the current rate of change continues:

```
weeks_until_breach = headroom_absolute / rate_of_change_per_week
```

This is a rough projection, not a prediction -- present it as "at the current
rate of degradation, this metric could breach in approximately N weeks."

### Step 9: Service-side correlation (when warranted)

If Step 7 reveals degradation, offer (don't auto-run) to correlate with
service-side data to separate **service degradation** (fix the service),
**test-environment changes** (load-zone latency, LG exhaustion), and
**script changes** (a slower edit). Present findings and ask first.

Hand off to `debug-with-grafana` (via `gcx`) to query the service's Prometheus
metrics and Loki logs for the same window; look for service error-rate changes,
upstream latency, resource pressure (CPU/memory/pools), and deploys coinciding
with inflection points.

**When the service has no observability** (third-party or another team's
service -- no Prometheus job, Loki stream, or probe), fall back to client-side
signal, which still localises the regression:

- **Browser tests:** compare Tempo iteration traces (k6-manage §7,
  `/api/v1/tempo/api/search` + `/traces/{id}`) for a before/after run. The
  span-name rollup, slowest spans, and per-URL navigation durations pin the
  regression to a URL, locator action, or asset; web vitals are `web_vital.*`
  span attributes -- read them directly.
- **Protocol tests:** compare `http_req_duration by (name, status)` and
  `http_req_failed by (name, status)`; a regression on one named request
  points at that endpoint. Split `http_req_waiting` (server time) vs
  `http_req_receiving` (transfer) to separate slow processing from slow download.
- **Payload corroboration** (both): query `data_received` /
  `browser_data_received`. Latency up + payload up -> server content changes;
  latency up + payload stable -> server processing changes; intermittent
  payload -> flaky cache or A/B test.

Prefer server-side correlation when available -- it answers "why" directly; the
fallbacks answer "where" and "what kind of change", and make a good ticket for
the owning team.

### Step 10: Present the report

Always present findings as a structured report. Never apply changes directly.

---

## Report template

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

---

## Threshold recommendations

- **Only tighten, never loosen** (unless asked) -- loosening masks problems.
- **Target 10-20% headroom** above the recent P95 -- room for variance, tight
  enough to catch real degradation.
- **Baseline on the second-half mean**, not the latest run (could be an outlier).
- **Respect intent**: very loose thresholds (>100% headroom) may be deliberate --
  mention the opportunity, don't push.
- **Grouped thresholds**: for tag-based thresholds
  (`http_req_duration{name:homepage}`), recommend per-endpoint values where
  trends differ.

---

## Gotchas

| Issue | Detail |
|-------|--------|
| **Zero-observation thresholds** | A threshold with zero observations passes by default in k6. If a metric appears to pass but has no data, flag it -- the threshold is not actually being evaluated. |
| **Metric type changes across runs** | If a metric's type changed between runs (e.g., script refactor), the multi-run aggregate endpoint uses the latest type. Earlier runs queried with the wrong method return empty. Flag this if detected. |
| **Incomplete runs skew trends** | Aborted or timed-out runs typically have shorter durations and fewer iterations, producing unrepresentative metric values. Exclude them by default. |
| **LG resource metrics** | `load_generator_cpu_percent` and `load_generator_file_handles` trending up may indicate the test is outgrowing its load generator allocation, not that the service is degrading. Call this out separately. |
| **Rate metric direction** | For `ratio`-type rate metrics (like check pass rates), "degrading" means the value is *decreasing* (fewer passes), which is the opposite direction from latency metrics. |
