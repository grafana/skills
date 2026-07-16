# Worked investigation example — what a "good" report looks like

> **Synthetic example.** Names, URLs, IDs, and the user email below are fictional placeholders. Replace them with your real stack / test / run when applying this recipe.

Investigating **test 100001 ("Search for products")** on `https://acme.grafana.net`. Run **999999** (manually triggered 2026-05-11) is used as the worked example — it's the first run in this test's history (out of 1177) to finish with `result: "failed"` rather than `"passed"`.

Use this file as a template for the Step 9 report in `SKILL.md`. For the *how* (fetching the data), see the workflow steps in `SKILL.md` and the underlying mechanics in `k6-manage` — this file just shows the *what*.

---

## Run summary

| Field | Value |
|---|---|
| Run ID | `999999` |
| Test ID | `100001` ("Search for products") |
| Created | `2026-05-11T16:00:25Z` |
| Ended | `2026-05-11T16:06:01Z` |
| Started by | `qa-agent@example.com` (manual) |
| Load zone | `amazon:gb:london` |
| Status | `completed` |
| Result | **`failed`** (first in the test's history) |

## Logs (from k6 cloud, 11 lines across 2 streams)

| Stream labels | Lines | Content |
|---|---|---|
| `source=console, level=info, lz=amazon:gb:london` | 10× | `navigating page: navigating frame to "https://shop.example.com/search": net::ERR_ADDRESS_UNREACHABLE` |
| `level=warning` | 1× | `The options.ext.loadimpact option is deprecated, please use options.cloud instead` |

So every iteration aborted at the navigation step (DNS or routing failure to `shop.example.com`). No HTTP request body, no DOM, no later log lines.

## Metrics (from the v5 k6 cloud API)

| Metric | Query | min | median | max | n datapoints |
|---|---|---|---|---|---|
| `checks` | `ratio` | 0.0 | 0.0 | 0.0 | 10 |
| `checks` | `rate_total` | 0.33/s | 0.33/s | 0.33/s | 10 |
| `iterations` | `value` (cumulative) | 1 | 5.5 | 10 | 10 |
| `iteration_duration` | `histogram_avg` | 3,462 ms | 6,500 ms | 6,588 ms | 10 |
| `browser_http_req_duration` | `histogram_avg` | 3,001 ms | 3,001 ms | 3,005 ms | 10 |
| `browser_web_vital_ttfb` | `histogram_avg` | 3,002 ms | 3,003 ms | 3,006 ms | 9 |
| `browser_web_vital_fcp` | `histogram_avg` | 3,168 ms | 6,230 ms | 6,340 ms | 8 |
| `browser_data_received` | `increase` | 114 B | 114 B | 114 B | 10 |

## Per-check breakdown (v5 `checks` metric, `ratio by (check)`)

| Check name | Success ratio | Successes | Failures |
|---|---|---|---|
| `script completed without exception` | 0.0 | 0 | 10 |

## Interpretation

- All 10 iterations completed (`iterations` reached 10), each ~6.5 s.
- `browser_http_req_duration` clusters tightly at exactly **3 s** — that's a connection timeout firing.
- `checks` ratio = 0% on every datapoint — the patched script's catch block correctly forced a `check(null, …false)` observation. The threshold `'checks{check:script completed without exception}': ['rate==1.0']` then evaluated to false → `result: "failed"`.

## Diagnosis

`shop.example.com` was unreachable from `amazon:gb:london` for the duration of the run. The 3-second clustering on `browser_http_req_duration` is the connection-establishment timeout in Chromium. The threshold-based failure detection worked exactly as intended: the catch block recorded a forced check failure on every aborted iteration, the threshold saw `rate=0.0` against `rate==1.0`, and `result` flipped to `failed`. No script bug — this is an external/infrastructure issue to investigate (DNS, peering, or upstream availability of `shop.example.com`).

---

## Concrete commands used to gather the above

Sample IDs: `RUN=999999`, `TEST_ID=100001`, `START=1778515225`, `END=1778515561`, `STACK=acme`. All paths use the doubled `cloud/cloud/` plugin-proxy prefix (see `k6-manage` §2).

```bash
# Run metadata (v6 REST)
gcx --context $STACK api \
  /api/plugins/k6-app/resources/cloud/cloud/v6/test_runs/$RUN

# Logs (Loki via gcx api — full recipe in k6-manage §4)
QUERY=$(printf '{test_run_id="%s"}' "$RUN" | jq -sRr @uri)
gcx --context $STACK api \
  "/api/plugins/k6-app/resources/logs/api/v1/query_range?query=${QUERY}&direction=backward&start=${START}&end=${END}&limit=1000" \
  -H "X-K6TestRun-Id: ${RUN}"

# List metrics emitted by the run (v5; see k6-manage/references/metrics.md §1)
gcx --context $STACK api \
  /api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/$RUN/metrics

# Per-check pass rate (v5 query_aggregate_k6 on the `checks` rate metric)
gcx --context $STACK api \
  "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/$RUN/query_aggregate_k6(query='ratio by (check)',metric='checks')"

# Raw success/failure counts per check
gcx --context $STACK api \
  "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/$RUN/query_aggregate_k6(query='increase_nz by (check)',metric='checks')"
gcx --context $STACK api \
  "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/$RUN/query_aggregate_k6(query='increase_z by (check)',metric='checks')"

# p95 request latency by endpoint/status (v5 query_range_k6 on a trend metric)
gcx --context $STACK api \
  "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/$RUN/query_range_k6(query='histogram_quantile(0.95) by (name,status)',metric='http_req_duration',step=10)"

# Label discovery for browser tests — what URLs/statuses were recorded?
gcx --context $STACK api \
  "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/$RUN/labels?match[]=browser_http_req_duration"
gcx --context $STACK api \
  "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/$RUN/label/url/values?match[]=browser_http_req_duration"
gcx --context $STACK api \
  "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/$RUN/label/status/values?match[]=browser_http_req_duration"
```

Converting the run's ISO timestamps to the unix seconds the Loki query expects: see the `START`/`END` conversion idiom in `k6-manage` §4 (uses `jq`'s `fromdateiso8601`, with a `.fraction` strip for k6's sub-second precision).
