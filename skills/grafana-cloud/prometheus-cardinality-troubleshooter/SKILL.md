---
name: prometheus-cardinality-troubleshooter
license: Apache-2.0
description: >
  Diagnostic guide for active Prometheus cardinality problems — slow queries, OOMing
  Prometheus, high Grafana Cloud Active Series or DPM bills, "too many samples" ingest
  errors, series churn, or rapid memory growth. Walks through tsdb status endpoints,
  per-metric and per-label drill-downs, common-culprit galleries, and remediation paths.
  Use when the user is *currently experiencing* a cardinality fire. For preventing
  cardinality issues at the source, route to prometheus-label-strategy. For post-ingest
  aggregation, route to adaptive-metrics. For DPM-specific analysis, route to dpm-finder.
---

# Prometheus Cardinality Troubleshooter

You are an expert in diagnosing live Prometheus cardinality problems. When a user reports a Prometheus performance, memory, or cost issue that smells like cardinality, use this guide to triage systematically.

This skill is **diagnostic and operational**. For schema design and prevention, route to `prometheus-label-strategy`.

---

## Before You Remediate: The One Rule

Under pressure, the tempting move is to `labeldrop` the high-cardinality label at scrape time. **Do not.** You cannot remove, at scrape time, any label that makes a series unique — not `pod`, not `instance`, not anything that distinguishes one real series from another. It looks like it stops the bleeding; it actually **breaks the data**:

- Counter resets from different series get merged → `rate()` and `increase()` return garbage, often *absurdly high* values.
- Multiple samples land on the same series per scrape → duplicate-sample / out-of-order errors and **inflated** DPM, not reduced.
- The breakage is silent (no config error) and leaves no evidence in the data of where it went wrong. Weeks later someone asks "why is my DPM so high / why is `rate()` absurd?" and there's nothing to point to.

The only safe remediations are:

1. **Drop an *entire* unwanted metric** (`action: drop` on `__name__`) — you're discarding the whole metric, not merging distinct series.
2. **Fix the source** — stop the application emitting the bad label (the real fix for unbounded `path`, `user_id`, etc.).
3. **Adaptive Metrics** — for structural cardinality on series you can't fix at the source. It aggregates *correctly* (counter-reset-aware, audited, reversible). This is the right way to reduce the cost of a label like `pod`. Route to `adaptive-metrics`.

Everywhere below that says "drop a label," read it through this rule: drop whole metrics, fix the source, or use Adaptive Metrics — never `labeldrop` a distinguishing label.

---

## Symptom → Likely Cause

| Symptom | Likely Cause | First Action |
|---|---|---|
| Prometheus OOMKilled or memory growing linearly | Active series growth (often from a new bad metric or label) | [Active Series triage](#step-1-active-series-triage) |
| Single PromQL query slow or OOMs the querier | One or more metrics in the query have high cardinality | [Per-query drill-down](#step-3-per-metric-drill-down) |
| Remote write lagging, WAL growing | Sample throughput spike — series count OR scrape interval changed | [Active Series triage](#step-1-active-series-triage) + check scrape intervals |
| `429 Too Many Samples` / `out of bounds` errors | Hitting Mimir/Cortex ingester per-tenant series limit | [Per-metric drill-down](#step-3-per-metric-drill-down), find the new offender |
| Grafana Cloud Active Series bill spiked | New metric, new label, or rollout creating churn | [Per-metric drill-down](#step-3-per-metric-drill-down) + churn check |
| Grafana Cloud DPM bill spiked but Active Series flat | Scrape interval shortened, OR remote_write sending duplicates | DPM-side issue — route to `dpm-finder` |
| `series_limit_per_user` errors after a deploy | Application change introduced a new bad label | [Recent change diff](#step-4-recent-change-diff) |
| Series count grows then resets every restart | Series churn from ephemeral label values | [Churn diagnosis](#step-5-churn-diagnosis) |

---

## Step 1: Active Series Triage

### Get the headline number

```promql
# Total active series in the local Prometheus
prometheus_tsdb_head_series

# Or for Mimir / Grafana Cloud Metrics (per tenant)
cortex_ingester_memory_series{user="<tenant>"}
```

Compare to recent history:
```promql
# Growth over the last 7 days
deriv(prometheus_tsdb_head_series[7d]) * 86400
```

A growth rate > a few % per day on a stable application set is a red flag.

### Use the TSDB status endpoint

Prometheus exposes a built-in cardinality breakdown:

```bash
curl -s http://prometheus:9090/api/v1/status/tsdb | jq
```

Returns:
- `seriesCountByMetricName` — top metrics by series count
- `labelValueCountByLabelName` — top labels by unique value count
- `memoryInBytesByLabelName` — top labels by memory footprint
- `seriesCountByLabelValuePair` — top label-value pairs by series count

This is usually the fastest path to "which metric / which label is the problem."

For Grafana Cloud:
```bash
# Same endpoint, authenticated against the per-tenant Mimir
curl -s -u "<user>:<token>" \
  "https://prometheus-prod-XX.grafana.net/api/prom/api/v1/status/tsdb" | jq
```

---

## Step 2: Read the Output

### Top metrics by series count

```json
"seriesCountByMetricName": [
  { "name": "http_request_duration_seconds_bucket", "value": 184320 },
  { "name": "go_gc_duration_seconds",               "value": 80 },
  ...
]
```

**Heuristics**:
- A histogram (`_bucket`) at the top is almost always the answer — those have a 14× multiplier (bucket count + 3). The fix is usually **reducing the labels on the underlying histogram at the source** (in instrumentation code), not stripping them at scrape and not touching the buckets themselves.
- A metric in the top 5 you don't recognize → grep the codebase for it; it's likely a new feature flag or a debug metric that shipped to prod
- The same metric showing up under multiple variants (`_total`, `_count`, `_sum`) — that's a histogram or summary, count all variants together for the true impact

### Top labels by unique value count

```json
"labelValueCountByLabelName": [
  { "name": "url",       "value": 84210 },
  { "name": "trace_id",  "value": 41000 },
  { "name": "pod",       "value": 1820 }
]
```

**Red flags**:
- Any label with >10K unique values is almost certainly a bug. The only exceptions are intentional per-target labels in massive fleets.
- `trace_id`, `request_id`, `session_id`, `query`, `email`, `path`, `url` — these should *never* be labels. They belong in exemplars, logs, or traces.
- `pod` with thousands of values — see [Churn diagnosis](#step-5-churn-diagnosis); recent churn often inflates this number

---

## Step 3: Per-Metric Drill-Down

Once you've identified a suspect metric, find which label is responsible.

### Count distinct label values per label, for one metric

```promql
# How many unique values does each label have on this metric?
count by (__name__) (
  count by (__name__, label_name_here) (
    http_request_duration_seconds_bucket
  )
)
```

Repeat per label, or use the helper:

```bash
# Via the Prometheus HTTP API
curl -s "http://prometheus:9090/api/v1/labels?match[]=http_request_duration_seconds_bucket" | jq -r '.data[]' | \
  while read label; do
    count=$(curl -s "http://prometheus:9090/api/v1/label/${label}/values?match[]=http_request_duration_seconds_bucket" | jq '.data | length')
    echo "${count}  ${label}"
  done | sort -rn | head -20
```

### Find the top label values for one label

```promql
# Top 20 path values for http_requests_total
topk(20,
  count by (path) (http_requests_total)
)
```

If you see UUIDs, hashes, timestamps, or numeric IDs in the top values → that label has unbounded values from the source.

### Per-metric series count, grouped

```promql
# Series-per-instance breakdown — if uneven, one instance is misbehaving
sum by (job, instance) ({__name__=~"my_metric.*"})
```

---

## Step 4: Recent Change Diff

If the cardinality fire started recently, the cause is almost always a recent change. Diff what's there now against what was there before.

### List of metrics, current vs. yesterday

Via Grafana Cloud cardinality dashboard, or:
```promql
# Current metrics
group by (__name__) ({__name__!=""})

# Compare to last week (offset)
group by (__name__) ({__name__!=""} offset 7d)
```

Diff externally. A new metric near the top of `seriesCountByMetricName` that wasn't there a week ago → that's your offender.

### Correlate with deploys

```promql
# Active series correlated with build_info
prometheus_tsdb_head_series
# Overlay with:
changes(app_build_info[1d])
```

A vertical step in series count aligned with a deploy is conclusive.

---

## Step 5: Churn Diagnosis

High churn means series are being created and abandoned faster than they age out. Symptoms: series count keeps climbing, then drops sharply on Prometheus restart.

### Churn signal

```promql
# Series created vs. removed per second
rate(prometheus_tsdb_head_series_created_total[5m])
rate(prometheus_tsdb_head_series_removed_total[5m])

# Ratio of churned to live
prometheus_tsdb_head_series_created_total / prometheus_tsdb_head_series
```

A creation rate that materially exceeds the removal rate, sustained, means cardinality is on a one-way trip up. Common causes:

| Cause | Tell |
|---|---|
| Pod rollouts emitting `pod` label | Churn spike aligns with deploy timing; affects pod-discovered scrapes |
| `version` / `git_sha` / `image_tag` label on every metric | Churn spike on every deploy across many metrics |
| Ephemeral hostnames in `instance` | Cloud autoscaling event timing |
| Bug: dynamic label names | Churn climbs forever, never plateaus |
| Application bug emitting fresh UUIDs as labels | Linear unbounded growth, no deploy correlation |

### Memory impact of churn

```promql
# A churn-driven head block carries old series until tsdb compaction
prometheus_tsdb_head_chunks
go_memstats_heap_inuse_bytes{job="prometheus"}
```

Restarting Prometheus drops churned series but is not a fix. The fix is at the source.

---

## Common-Culprit Gallery

### Histogram blowup

**Tell**: `*_bucket` metric at the top of `seriesCountByMetricName`. Multiplier ≈ 14×.

**Fix**:
1. First, **reduce labels on the histogram at the source** — every label removed saves 14× series. Trim `path`, `method`, or `status_code` in the instrumentation code (don't `labeldrop` them at scrape — that merges distinct histograms and corrupts the buckets). For series already in Grafana Cloud you can't change, aggregate them with Adaptive Metrics.
2. Then, reduce bucket count if appropriate (custom buckets vs. defaults).
3. For high-resolution latency tracking, consider **native histograms** (Prometheus 2.40+) — single sparse series replaces the bucket family.

### kube-state-metrics label explosion

**Tell**: `kube_pod_labels` or `kube_pod_annotations` at the top, with `label_*` or `annotation_*` labels driving cardinality.

**Fix**: configure kube-state-metrics with `--metric-labels-allowlist` and `--metric-annotations-allowlist`. By default it emits *all* labels and annotations as series.

```yaml
# kube-state-metrics flags
--metric-labels-allowlist=pods=[app,team,version]
--metric-annotations-allowlist=pods=[checksum/config]
```

### Path / route blowup from a new endpoint

**Tell**: `http_requests_total` (or framework equivalent) grew 10×+ overnight. `topk(20, count by (path) (http_requests_total))` shows hundreds of `/users/123456`-style values.

**Fix**: the real fix is to **template the path in application code** (`/users/:id`) — route the user to `prometheus-label-strategy`. For series already in Grafana Cloud, **Adaptive Metrics** can aggregate `path` away correctly — route to `adaptive-metrics`.

Do **not** "normalize" `path` with a relabel `replacement` rule — collapsing `/users/123`, `/users/456`, … into one `/users/:id` value at scrape merges distinct series and produces duplicate-sample errors and broken `rate()`. The merge has to happen at the source (templating) or post-ingest (Adaptive Metrics), never at scrape.

If you must stop a production fire *right now* and templating isn't deployable yet, the only safe scrape-time action is to drop the **entire** offending metric (you lose it completely until the code fix lands — a deliberate trade, not a silent corruption):

```yaml
# Emergency: drop the whole metric until the source is templated
metric_relabel_configs:
  - source_labels: [__name__]
    regex: http_requests_total
    action: drop
```

### Application emitting a debug metric in prod

**Tell**: A metric you don't recognize in the top 10. Grep the source — often a `_details` or `_per_request` debug metric the developer forgot to gate.

**Fix**: drop entirely at scrape:
```yaml
metric_relabel_configs:
  - source_labels: [__name__]
    regex: my_app_request_details
    action: drop
```

Open a ticket against the team to remove it from the code.

### App-emitted labels colliding with target labels

**Tell**: Series count for one job is several × what it should be. Looking at one series, you see both an app-emitted `instance=...` AND the target `instance=...` collided into something weird (Prometheus renames the conflicting one to `exported_instance`).

**Fix**: the right fix is **in the application** — stop emitting `instance`/`node`/`host` from code; they belong to the scrape target. Confirm `honor_labels` is `false` (the default) so the target labels win.

If you need a scrape-time stopgap, you may remove a label *only* where it **exactly duplicates** a target label — that's the one safe `labeldrop`, because the target label still provides uniqueness. Scope it tightly to the duplicated names and **never include `pod`** (or any other label that is the source of uniqueness):

```yaml
# Stopgap ONLY for app-emitted duplicates of target labels.
# Drops the `exported_*` collisions — NOT pod, which makes K8s series unique.
metric_relabel_configs:
  - regex: exported_(instance|node|host)
    action: labeldrop
```

Then the target labels from `relabel_configs` apply cleanly. Prefer fixing the app.

### Federation amplifying cardinality

**Tell**: A federated Prometheus or Mimir global view has way more series than expected. Each source has its own `cluster` / `region` label, multiplying.

**Fix**: this is usually expected — federation by design preserves source labels. If the series count is too high, federate only aggregated recording rules, not raw metrics:

```yaml
- job_name: federate
  honor_labels: true
  metrics_path: /federate
  params:
    'match[]':
      - '{__name__=~".*:.*"}'  # Recording-rule naming convention only
```

---

## Remediation Decision Tree

```
Cardinality fire confirmed
│
├── Need to stop the bleeding NOW (production OOM, ingest 429s)
│   └── Drop the ENTIRE offending metric via metric_relabel_configs (action: drop on __name__)
│       (also applies to Alloy/Agent — same syntax)
│       Do NOT labeldrop a distinguishing label — it breaks the data, see "The One Rule".
│       Then schedule the proper fix.
│
├── It's a Grafana Cloud Active Series bill issue, not a perf issue
│   ├── Cardinality is structural and you can't fix the app
│   │   └── Route to `adaptive-metrics` skill (post-ingest aggregation rules — the safe way)
│   └── You want metric-by-metric DPM breakdown
│       └── Route to `dpm-finder` skill
│
├── It's a fixable application bug (unbounded label, debug metric in prod)
│   ├── Short-term: drop the whole metric at scrape, OR aggregate via Adaptive Metrics
│   └── Long-term: fix in code; route to `prometheus-label-strategy` for design guidance
│
├── It's histogram cardinality
│   ├── Reduce labels on the underlying histogram AT THE SOURCE (14× win per label)
│   ├── Reduce bucket count if appropriate
│   └── Consider native histograms for high-resolution latency
│
└── It's churn (deploy-driven)
    ├── Stop EMITTING `version`/`git_sha`/`instance` from app code (use info-metric for version)
    ├── Keep `pod` — never drop it; if pod-level series are too costly, use Adaptive Metrics
    └── Verify K8s SD relabel rules aren't mapping in `uid` or other ephemeral fields
```

---

## Emergency Drop Patterns (copy-paste ready)

These are the **safe** scrape-time emergency actions: dropping an *entire* unwanted metric. They do not merge distinct series, so they don't corrupt the data.

> ⚠️ There is intentionally **no `labeldrop` of a distinguishing label** and **no value-normalizing relabel** here. Both merge distinct series and break `rate()`/DPM (see [The One Rule](#before-you-remediate-the-one-rule)). To reduce cardinality *without* dropping the whole metric, fix the source or use **Adaptive Metrics** (route to `adaptive-metrics`). The only safe `labeldrop` is removing a label that *exactly duplicates* a target label (e.g. `exported_instance`) — see [App-emitted labels colliding with target labels](#app-emitted-labels-colliding-with-target-labels).

For Prometheus `scrape_configs`:

```yaml
metric_relabel_configs:
  # Drop a specific bad metric entirely
  - source_labels: [__name__]
    regex: bad_metric_name
    action: drop

  # Drop a set of debug/temporary metrics by name prefix
  - source_labels: [__name__]
    regex: debug_.*
    action: drop
```

For Grafana Alloy (`prometheus.relabel` component):

```alloy
prometheus.relabel "drop_bad_metric" {
  forward_to = [prometheus.remote_write.default.receiver]

  rule {
    source_labels = ["__name__"]
    regex = "bad_metric_name"
    action = "drop"
  }
}
```

**Always test in staging first**, and prefer fixing the source or using Adaptive Metrics over any scrape-time drop.

---

## When to Hand Off

- **"Now design a label strategy so this doesn't happen again"** → `prometheus-label-strategy`
- **"We need to keep these metrics but reduce cost"** → `adaptive-metrics`
- **"Which metric is the most expensive in DPM terms?"** → `dpm-finder`
- **"Write the PromQL to find this"** → `promql`
- **"Configure this in Alloy"** → `alloy`
- **"Why is my Loki slow?"** → `loki-label-analyzer` (different system, same family of problems)

This skill's lane is **diagnosis under pressure**. Prevention, design, and post-ingest cost optimization live elsewhere.
