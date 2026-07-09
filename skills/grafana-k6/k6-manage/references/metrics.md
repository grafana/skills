# Grafana Cloud k6 — Metrics REST API reference

Reference for the **v5** metrics endpoints. Mirrored from
<https://grafana.com/docs/grafana-cloud/testing/k6/reference/cloud-rest-api/metrics/>
so the agent can answer metrics questions without a web fetch every time.

## Calling via `gcx api`

The raw k6 paths in this doc start with `/cloud/v5/...`. To call them via
the Grafana plugin proxy (which is what `gcx api` uses), prefix them
with `/api/plugins/k6-app/resources/cloud/` — same doubled-`cloud/`
pattern as v6 (see SKILL.md §2). Example mapping:

| k6 path                                              | gcx invocation                                                                            |
|------------------------------------------------------|-------------------------------------------------------------------------------------------|
| `/cloud/v5/test_runs/{id}/metrics`                   | `gcx api /api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/{id}/metrics`             |
| `/cloud/v5/test_runs/{id}/query_range_k6(...)`       | `gcx api "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/{id}/query_range_k6(...)"` |

`Authorization` and stack scoping are injected by gcx — do not set them.

**Quoting tip**: the `query_range_k6(...)` / `query_aggregate_k6(...)`
endpoints use OData function-call URL syntax with single-quoted string
arguments. Wrap the whole path in double quotes when invoking `gcx api`
so the inner single quotes survive shell parsing.

There is also an alternative `/ms` alias for the load-test-level
endpoints (used by the k6 UI to dodge ad-blockers); from `gcx api` you
don't need it.

---

## Endpoints

### 1. List metrics for a single test run

`GET /cloud/v5/test_runs/{testRunId}/metrics`

Returns every metric emitted by a run.

```bash
gcx api /api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/152779/metrics
```

Response fields per metric:

- `id` (string)
- `name` (string) — e.g. `http_req_duration`, `vus`, `data_sent`
- `origin` (string) — e.g. `builtin`
- `test_run_id` (integer)
- `type` (string) — one of `counter`, `gauge`, `trend`, `rate`

The metric's `type` determines which query methods are valid against it
(see "Query methods" below).

### 2. List metrics across multiple test runs

#### Last N runs of a load test

`GET /cloud/v5/load_tests/{loadTestId}/metrics(test_run_count={n})`

```bash
gcx api "/api/plugins/k6-app/resources/cloud/cloud/v5/load_tests/1529/metrics(test_run_count=5)"
```

`test_run_count` defaults to 30 if omitted.

#### Specific runs by ID

`GET /cloud/v5/load_tests/{loadTestId}/metrics(test_run_ids=[{id1},{id2},...])`

```bash
gcx api "/api/plugins/k6-app/resources/cloud/cloud/v5/load_tests/1529/metrics(test_run_ids=[152779,152782,152785])"
```

Response per metric:

- `name` (string)
- `type` (string) — if a metric has different types across the selected
  runs, the **latest** run's type wins
- `labels` (array of strings) — union of label names seen across the
  selected runs

Results are alphabetised by name.

### 3. List time series

`GET /cloud/v5/test_runs/{testRunId}/series?match[]=<selector>&...`

Prometheus-like series API: returns the set of label combinations that
match each selector. Repeat `match[]` for multiple selectors; at least
one is required.

```bash
gcx api "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/152777/series?match[]=http_req_duration{expected_response=\"true\"}"
```

Response:

```json
{
  "status": "success",
  "data": [
    {"__name__": "http_req_duration", "expected_response": "true", "name": "...", "test_run_id": "152777", ...}
  ]
}
```

### 4. List label names

`GET /cloud/v5/test_runs/{testRunId}/labels?match[]=<selector>`

`match[]` is optional; without it, all labels for the run are returned.

```bash
gcx api "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/152777/labels?match[]=http_req_duration"
```

Response:

```json
{
  "status": "success",
  "data": ["__name__", "expected_response", "group", "load_zone", "method", "name", "proto", "scenario", "status", "test_run_id", "url"]
}
```

### 5. List label values

`GET /cloud/v5/test_runs/{testRunId}/label/{labelName}/values?match[]=<selector>`

```bash
gcx api "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/152777/label/load_zone/values?match[]=http_req_duration"
```

Response:

```json
{"status": "success", "data": ["amazon:us:columbus", "amazon:eu:dublin"]}
```

### 6. Query a range (time series)

`GET /cloud/v5/test_runs/{testRunId}/query_range_k6(query='...',metric='...',step=...,start=...,end=...)`

Returns one sample per `step` seconds over `[start, end]`. Parameters
go **inside the parens**, comma-separated, with string values in single
quotes.

Parameters:

| Name     | Required | Notes                                                                |
|----------|----------|----------------------------------------------------------------------|
| `query`  | yes      | Query expression (see "Query methods" / "Aggregation" below)          |
| `metric` | yes      | Metric name with optional selector — `http_req_duration{status="200"}` |
| `step`   | no       | Sample interval in seconds                                            |
| `start`  | no       | ISO 8601; defaults to test run start                                  |
| `end`    | no       | ISO 8601; defaults to test run end                                    |

```bash
gcx api "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/152779/query_range_k6(query='increase by (name,status)',metric='http_reqs{status!=\"0\"}',step=5)"
```

Response shape (matrix):

```json
{
  "status": "success",
  "data": {
    "resultType": "matrix",
    "result": [
      {
        "metric": {"__name__": "http_reqs", "name": "login page", "status": "200", "test_run_id": "152779"},
        "values": [[1684949415, 845], [1684949420, 1034]]
      }
    ]
  }
}
```

### 7. Query an aggregate (single value)

`GET /cloud/v5/test_runs/{testRunId}/query_aggregate_k6(query='...',metric='...',start=...,end=...)`

Same shape as `query_range_k6` but collapses the window into one value
per series.

```bash
gcx api "/api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/152779/query_aggregate_k6(query='histogram_quantile(0.95) by (name,status)',metric='http_req_duration')"
```

Response shape (vector):

```json
{
  "status": "success",
  "data": {
    "resultType": "vector",
    "result": [
      {
        "metric": {"__name__": "http_req_duration", "name": "...", "status": "200", "test_run_id": "152779"},
        "values": [[1684950639, 14207]]
      }
    ]
  }
}
```

### 8. Aggregate across multiple runs

`GET /cloud/v5/load_tests/{loadTestId}/query_aggregate_k6(...)`

Same parameters as the single-run version, plus one of:

- `test_run_count={n}` — last N runs
- `test_run_ids=[{id1},{id2},...]` — explicit list

```bash
gcx api "/api/plugins/k6-app/resources/cloud/cloud/v5/load_tests/1529/query_aggregate_k6(query='histogram_quantile(0.95)',metric='http_req_duration',test_run_count=10)"
```

Results include `test_run_id` as a label so you can distinguish runs in
the response.

---

## Selector syntax

Selectors look like `metric_name{label_op="value", ...}`. Operators:

| Operator | Meaning             |
|----------|---------------------|
| `=`      | Exact match         |
| `!=`     | Not equal           |
| `=~`     | Regex match         |
| `!~`     | Regex non-match     |

Examples:

```
http_req_duration
http_req_duration{status="200"}
http_req_duration{status=~"(2|3)\d\d"}
http_req_duration{status!="0"}
http_req_duration{status!="0",name="login page"}
```

---

## Query methods

The valid methods depend on the metric's `type`. Pick from the matching
table below; passing a counter method to a trend metric (or vice versa)
will return an error or empty result.

### Counter methods

| Method                   | Description                                |
|--------------------------|--------------------------------------------|
| `increase`               | Total increase across the window            |
| `rate`                   | Average increase per second                 |
| `value`                  | Current counter value                       |
| `cumrate`                | Cumulative rate from test start             |
| `max_rate(<interval>)`   | Peak rate within a sliding window (seconds) |

### Gauge methods

| Method      | Description                          |
|-------------|--------------------------------------|
| `last`      | Last observed value                  |
| `min`       | Minimum observed value               |
| `max`       | Maximum observed value               |
| `avg`       | Average of observations              |
| `last_time` | Timestamp of the last observation    |

### Rate methods

For rate metrics (true/false observations like `check{...}`):

| Method            | Description                                 |
|-------------------|---------------------------------------------|
| `increase_total`  | Total of all observations                   |
| `rate_total`      | Avg rate per second of all observations     |
| `value_total`     | Current total                               |
| `increase_nz`     | Total of **non-zero** (true) observations   |
| `rate_nz`         | Avg rate per second of non-zero             |
| `value_nz`        | Current non-zero value                      |
| `increase_z`      | Total of **zero** (false) observations      |
| `rate_z`          | Avg rate per second of zero                 |
| `value_z`         | Current zero value                          |
| `ratio`           | Fraction of non-zero to total               |

### Trend methods

For latency/duration trend metrics:

| Method                           | Description                       |
|----------------------------------|-----------------------------------|
| `histogram_max`                  | Max value                         |
| `histogram_min`                  | Min value                         |
| `histogram_avg`                  | Mean                              |
| `histogram_stddev`               | Standard deviation                |
| `histogram_quantile(<q>)`        | Quantile, `q` in `[0, 1]`         |
| `histogram_count_increase`       | Increase in observation count     |
| `histogram_count_value`          | Current observation count         |

---

## Aggregation across labels

### Keep selected labels

`<method> by (<label1>,<label2>,...)` returns one series per distinct
combination of the listed labels:

```
histogram_quantile(0.95) by (name,status)
max by (instance_id)
```

### Cross-label aggregator

Wrap a method expression in an aggregator (`min`, `max`, `sum`, `avg`)
to collapse across the inner labels, optionally regrouping with `by`:

```
sum(last by (instance_id))                      # total of per-instance last values
avg(rate by (name, method)) by (method)         # mean rate per method, across endpoints
```

---

## Common metric names

| Metric                          | Type     | Meaning                       |
|---------------------------------|----------|-------------------------------|
| `http_req_duration`             | trend    | Request latency               |
| `http_reqs`                     | counter  | Total HTTP requests           |
| `vus`                           | gauge    | Virtual users in flight       |
| `data_sent`                     | counter  | Bytes sent                    |
| `iteration_duration`            | trend    | Time per iteration            |
| `load_generator_file_handles`   | gauge    | Open file handles on LG       |
| `load_generator_cpu_percent`    | gauge    | LG CPU usage                  |

The full list for a given run comes from endpoint §1
(`/test_runs/{id}/metrics`); k6 emits more (and users can emit
custom metrics from their scripts).

---

## Worked queries

```text
# VU count over time
query_range_k6(metric='vus', query='sum(last by (instance_id))')

# Requests per second
query_range_k6(metric='http_reqs', query='rate')

# RPS excluding network errors, per endpoint+method
query_range_k6(metric='http_reqs{status!="0"}', query='rate by (name,method)')

# p95 response time, 10s resolution, per endpoint+method+status
query_range_k6(metric='http_req_duration', query='histogram_quantile(0.95) by (name,method,status)', step=10)

# Total HTTP requests over the whole run
query_aggregate_k6(metric='http_reqs', query='increase')

# Total requests in a sub-window
query_aggregate_k6(metric='http_reqs', query='increase', start=2021-08-09T12:01:10Z, end=2021-08-09T12:09:13Z)

# p95 latency per endpoint+method+status
query_aggregate_k6(metric='http_req_duration', query='histogram_quantile(0.95) by (name,method,status)')

# Peak RPS (5s windows) for 2xx/3xx by endpoint
query_aggregate_k6(metric='http_reqs{status=~"[23][0-9]{2}"}', query='max_rate(5) by (name)')

# Peak CPU per LG, averaged across LGs
query_aggregate_k6(metric='load_generator_cpu_percent', query='avg(max by (instance))')

# Peak VUs across the run
query_aggregate_k6(metric='vus', query='sum(max by (instance_id))')
```

---

## Gotchas

- **OData function-call syntax, not query strings.** `query`, `metric`,
  `step`, `start`, `end`, `test_run_count`, `test_run_ids` go *inside*
  the parens, comma-separated. They are not URL query params and
  putting them after a `?` will fail.
- **Mind the shell quoting.** Single quotes around string arguments are
  part of the URL; wrap the whole `gcx api` argument in double quotes
  so they survive.
- **Method must match metric type.** `histogram_quantile` on a counter,
  or `rate` on a trend, will return nothing useful. Check the metric's
  `type` via endpoint §1 first.
- **Multi-run type collisions.** When listing metrics across runs (§2),
  if the metric's type differs between runs you only see the latest
  run's type. Aggregations using methods from the older type silently
  break.
- **Use `test_run_id` to distinguish in multi-run responses.** It
  appears as a label so you can split results by run.
