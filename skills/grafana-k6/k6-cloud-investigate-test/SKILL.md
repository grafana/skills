---
name: k6-cloud-investigate-test
description: Investigate a Grafana Cloud k6 test — describe the script, list run history, identify pass/fail status, pull raw metric time-series and log lines for one or more runs, and (if asked) safely edit the test script. Use when the user asks about a specific k6 cloud test or run, gives a `/a/k6-app/tests/<id>` or `/a/k6-app/runs/<id>` URL, asks "is this test passing", "why are my k6 tests failing", "show me metrics for run X", "show me logs for run X", or wants to add thresholds / fix a failing test. Trigger this skill even when the user doesn't explicitly say "investigate" — pasted `/a/k6-app/...` URLs, "why did run X fail", "what happened with my test", "is my test healthy", "the latest run looks weird", "checks are failing but the run says passed", or any request to diagnose a Grafana Cloud k6 run all qualify.
---

# k6 Cloud test investigator

Structured 9-step workflow for investigating a Grafana Cloud k6 test or run.

This skill is **workflow-only**. All API calls go through `gcx api` against the plugin proxy, using v6 for REST and v5 for metrics. For the underlying mechanics (gcx auth, path conventions, endpoint discovery, log queries, script editing, threshold semantics, gotchas), see the `k6-manage` skill — every step below references it.

The content unique to this skill is:

- the ordered investigation flow (Steps 1-9 below)
- the date-alignment check ("last 7 days" ≠ "last 7 runs")
- the 3-layer pass/fail determination (`result` vs `status` vs per-check `checks` query)
- a worked example with realistic numbers (`references/worked-example.md`)

## Core principles

1. **Read before write.** Always GET the script before any PUT. `gcx k6 load-tests update-script` is a *write* that replaces the live script with whatever file you pass — running it "just to see the URL it hits" has cost users their production scripts. If you need to learn URLs, run any non-mutating command with `-vvv` instead.
2. **Paginate when enumerating runs.** The `/test_runs` endpoint caps at 1000 rows and `gcx k6 runs list --limit 0` does not auto-follow `@nextLink`. Use the `gcx api` loop documented in `k6-manage` §3.
3. **Verify date framing.** When the user says "last 7 days", "this week", "recent runs" — confirm the most-recent run's `created` actually falls in that window. Surface the gap if not.
4. **`check()` doesn't fail runs; only `thresholds` do.** And thresholds with zero observations are reported as ✓ pass. See "Threshold semantics" below for the full deep dive; the per-check `checks` metric query in Step 5 catches both cases.

## Prerequisites

`gcx` installed and authenticated against the user's stack. See `k6-manage` §1. Verify with:

```bash
gcx --context <stack> config check    # expect "✔ Connectivity: online"
```

## Investigation workflow

### Step 1: Identify the test and target run(s)

From the user's URL:
- `/a/k6-app/tests/<id>` → load test (parent of many runs)
- `/a/k6-app/runs/<id>` → a specific run

To go run → test: fetch the run via `gcx api`, see `k6-manage` §2 for the path-shape rules:

```bash
gcx --context <stack> api /api/plugins/k6-app/resources/cloud/cloud/v6/test_runs/<run_id>
```

and read `.test_id` from the response. To list runs for a test, see Step 3.

### Step 2: Fetch test metadata and script

```bash
gcx --context <stack> k6 load-tests get <test_id> -o json
```

For the script, follow the GET half of the safe-edit recipe in `k6-manage` §5 — save a backup if you'll be editing later.

**Two script endpoints exist, and the difference matters for investigation.** `k6-manage` §5 documents both: the current load-test script and the per-run snapshot that was actually executed. They drift apart whenever the script is edited after a run. Whenever the question involves "what changed", "why did this run fail", or you're examining a run more than a few days old, also fetch the run-bundled snapshot(s) via `k6-manage` §5's run-script endpoint and diff against the current load-test script (or against another run's snapshot). The current load-test script is the wrong artifact to reason about a past run.

### Step 3: List runs WITH pagination

Use the `gcx api` + `@nextLink` loop pattern documented in `k6-manage` §3 against `/cloud/v6/load_tests/<test_id>/test_runs`. After collecting `all_runs`:

```python
print(f"Total: {len(all_runs)}")
runs_sorted = sorted(all_runs, key=lambda r: r['created'], reverse=True)
for r in runs_sorted[:10]:
    print(f"  {r['created']:30s} id={r['id']:>8} status={r['status']:<10} result={r.get('result','?')}")
```

Report to user: total run count, date range, latest run date. **If "latest run" is more than a day old**, call it out — they may believe the schedule is firing when it isn't.

### Step 4: Verify date alignment with user's intent

If the user asked for "last 7 days" / "this week" / "recent": filter by date range, not by row count — "7 most recent runs" could span a day or a year depending on how often the test runs.

```python
last7 = [r for r in all_runs if r['created'] >= '<today_minus_7_days_iso>']
```

If `len(last7) == 0`: surface this to the user immediately. Don't proceed with stale data.

### Step 5: Determine pass/fail status

For each run examine three independent layers:

| Layer | Field | Meaning |
|---|---|---|
| Run-level outcome | `result` (`passed` / `failed` / `error` / `aborted`) | Whether thresholds breached |
| Run-level status | `status` (`completed` / `aborted`) | Whether the run finished orderly |
| In-script checks | v5 `checks` metric, aggregated by the `check` label | Per-check success rate |

For a run that the user thinks is "failing" but reports `result: passed`: check the third layer. Common pattern: every iteration's `check()` returns false but the run still "passes" because no threshold is defined on `checks`. See "Threshold semantics" below for the full deep dive (zero-observation trap, `abortOnFail` cloud delay, operator support).

Query the per-check breakdown via v5 (see `k6-manage/references/metrics.md` §7 for `query_aggregate_k6` shape):

```bash
gcx --context <stack> api \
  "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/<run_id>/query_aggregate_k6(query='ratio by (check)',metric='checks')"
```

Each result entry in the response carries a `check` label with the check name and a single value: the success ratio (0.0–1.0). For raw success/fail counts, also query `increase_nz by (check)` (successes) and `increase_z by (check)` (failures).

### Step 6: Fetch metrics for a run

Use the v5 metrics endpoints documented in `k6-manage/references/metrics.md`. Typical workflow:

```bash
# 6a. List metrics available for the run (metrics.md §1)
gcx --context <stack> api /api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/<run_id>/metrics

# 6b. List labels for a metric to know what's available to filter/group by (metrics.md §4)
gcx --context <stack> api \
  "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/<run_id>/labels?match[]=http_req_duration"

# 6c. Time-series — pick a query method that matches the metric's type (metrics.md §6)
gcx --context <stack> api \
  "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/<run_id>/query_range_k6(query='histogram_quantile(0.95) by (name,status)',metric='http_req_duration',step=10)"

# 6d. Scalar aggregate over the whole run (metrics.md §7)
gcx --context <stack> api \
  "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/<run_id>/query_aggregate_k6(query='increase',metric='http_reqs')"
```

Picking the right query method per metric type matters — see the "Query methods" tables in `k6-manage/references/metrics.md`. For browser tests, the URL/status breakdown comes from `labels` + `label/{name}/values` (metrics.md §4/§5), not from a separate tags endpoint.

### Step 7: Fetch logs for a run

Follow the Loki recipe in `k6-manage` §4 (`gcx api` against `/api/plugins/k6-app/resources/logs/...`, `{test_run_id="<id>"}` selector, mandatory `X-K6TestRun-Id` header, scope `start`/`end` to `run.created`/`run.ended`). Save the response to `/tmp/run_<id>_logs.json` and summarise from the file as described there.

### Step 8: (If asked) edit the script safely

Use the full safe-edit recipe in `k6-manage` §5 (GET → backup → edit → `k6 inspect` → 1-iter smoke → PUT with `Content-Type: application/octet-stream` → sha256 verify).

When the edit involves thresholds, also read "Threshold semantics" below for the zero-observation trap, the `abortOnFail` cloud delay, and operator support (`==`/`!=` work despite docs).

### Step 9: Report

Pick a template based on the question shape.

**For single-run investigations** ("what's going on with run X"):

```
Test: <name> (id <test_id>)
Run:  <run_id> @ <created> → <ended>, load_zone=<zone>, result=<result>

Logs (<n> streams, <m> lines):
  - <stream summary>

Metrics (key indicators):
  - <metric>: <method> = <value> (n=<count>)
  ...

Per-check breakdown:
  - <check name>: <success_rate> (succ=<n>, fail=<n>)
  ...

Diagnosis: <one-paragraph>
```

**For multi-run comparisons** ("what's different between passing and failing runs", "did this change cause the failures"):

```
Question: <one-line restatement of what the user is trying to attribute>

Run timeline (relevant window):

| Run ID | Created (UTC) | Result | exec_duration | processing_duration | k6 build | error code | key check ratios |
|---|---|---|---|---|---|---|---|
| ... | ... | passed | 60s | 195s | <build> | — | 1.0/1.0/1.0 |
| ... | ... | failed | 27s | 193s | <build> | — | 0.0/n=0/n=0 |
| ... | ... | error  | 51s | 3601s aborted | <build> | 8016 | 1.0/1.0/1.0 |

Differences that matter:
  - <field>: <value-in-passing> vs <value-in-failing> — <interpretation>
  ...

Script diff (if relevant): <bundled-script diff between a representative passing and failing run, summarised>

Diagnosis: <one-paragraph attributing the change to test-side, SUT-side, or platform-side, with the supporting evidence>
```

The table makes side-by-side anomalies obvious (e.g. a column that's identical across passing and failing rules out that dimension as the cause; a column that flips between them is your candidate).

If the user asked for raw data dumps, also save them to `/tmp/k6inv/run<id>/` and tell them the paths.

## Threshold semantics

Thresholds, not `check()` calls, are what determine a run's `result`. The behaviour has several non-obvious corners that mislead first-time investigators, so they're collected here. Step 5 ("Determine pass/fail status") and Step 8 ("edit the script safely") both depend on this section.

### What `result` means

| `result` value | Meaning                                                       |
|----------------|---------------------------------------------------------------|
| `passed`       | All thresholds passed (or none defined)                       |
| `failed`       | At least one threshold failed                                 |
| `error`        | Either the script crashed before finishing (e.g. browser wouldn't launch) **or** k6 Cloud aborted the run platform-side. To tell which, check `status_history[*].extra.code` on the run — a non-null code indicates a platform abort (e.g. `8016` = "Test run max lifetime exceeded" during `processing_metrics`). Platform aborts are not your code's fault even though they surface as `error`. |
| `aborted`      | User or system aborted the run                                |

`check()` calls do **not** affect `result` directly. They emit observations into the built-in `checks` rate metric, which a threshold may then evaluate. If no threshold references `checks`, failing checks are invisible to the run-level `result`.

### The "zero observations = pass" trap

k6 reports a threshold as ✓ pass when the underlying metric has zero samples — even if the threshold expression would otherwise evaluate to false:

```
checks{check:response is 200}
✓ 'rate==1.0' rate=0.00%       ← ✓ pass!?
```

This bites when the script throws before reaching the relevant `check()` call. Force a check observation in a `catch` block to make the threshold see *something*:

```javascript
try {
  const r = await page.goto(URL);
  check(r, { "response is 200": x => x.status() === 200 });
  // ... rest of iteration body
  check(true, { "script completed without exception": () => true });
} catch (e) {
  console.error(e);
  check(null, { "script completed without exception": () => false });
} finally {
  await page.close();
}
```

Then add `'checks{check:script completed without exception}': ['rate==1.0']` to thresholds. This catches both navigation failures AND later-stage exceptions.

### `abortOnFail` cloud delay

> When k6 runs in the cloud, thresholds are evaluated every 60 seconds. The `abortOnFail` feature may be delayed by up to 60 seconds.

For runs shorter than 60 s, `abortOnFail` may not fire before iterations complete naturally. The threshold is still evaluated at end-of-run and `result` flips to `failed` — abort just doesn't save execution time.

### Operators

Docs show `<`, `>`, `<=`, `>=`. **`==` and `!=` also work** even though they aren't in the docs. For `rate` metrics (value 0.00–1.00), `rate==1.0` means "every observation was non-zero" and `rate==0` means "all observations were zero."

## Workflow-specific gotchas

For the canonical gotcha list (auth expiry, doubled `cloud/cloud/`, 415 on script PUT, Loki missing `X-K6TestRun-Id`, script PUT not bumping `updated`, `gcx k6 runs list --limit 0` not following `@nextLink`), see `k6-manage` §7. The entries below are specific to this investigation workflow:

| Symptom | Cause | Fix |
|---|---|---|
| "Latest run was 6 months ago" but schedule says daily | You didn't paginate `/test_runs` | Use the `@nextLink` loop in `k6-manage` §3 (Step 3) |
| "Last 7 days" report contains only old runs | Filtered by row count, not date | Re-filter by `created >= <iso_date>` (Step 4) |
| Threshold reports ✓ pass but checks fail | Zero check observations; iteration aborted before `check()` ran | See "Threshold semantics" above |
| `result: error` but the script logs/metrics look fine | Likely a platform abort (e.g. `processing_metrics` exceeded the 1h cap, `code 8016`). The execution itself completed normally. | Check `status_history[*].extra.code` on the run. Non-null platform code → not your code's fault. See "Threshold semantics" |
| Investigating a past run by reading the current load-test script | Script may have been edited since the run executed — what you're reading isn't what ran | GET the run's *bundled* script via the per-run endpoint (`k6-manage` §5) and diff against the current load-test script before drawing conclusions |
| Just overwrote the user's script | Invoked `update-script` to "see the URL" | Restore from the backup taken in Step 2. To learn URLs without writing, use `-vvv` on any non-mutating command. |
| CLI `--iterations 1` breaks browser scenarios | Overrides scenario block entirely | Edit `iterations:` in-file with sed instead |

## Reference

- [`references/worked-example.md`](references/worked-example.md) — a synthetic investigation with realistic findings, useful as a template for the Step 9 report.
