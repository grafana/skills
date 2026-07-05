# Backend investigation with Grafana

**Only applies if the customer owns the backend and has Grafana
access.** Skip this whole section if either is "no".

The goal: correlate k6's load-side signals (failed thresholds,
latency spikes, error rates) with backend-side signals (RED
metrics, error logs, profiles) to produce specific evidence.

## Non-negotiable: do not assume the stack

The skill is language-agnostic. **Do not** guess:

- Which language the backend is in (Go / Python / Java / Node /
  Rust / …).
- Which datasources are configured (Prom / Loki / Tempo /
  Pyroscope — any subset is possible).
- Which label keys identify the service (`service_name`, `service`,
  `app`, `job`, `namespace`, `container`, …).
- Which metric exposition is in use (default Prom exporters,
  OpenTelemetry, custom metrics).

Discover all of these from the live Grafana before formulating
queries.

## Step 1: discover datasources

Prefer `mcp-grafana` for in-session, structured discovery:

```
list_datasources()
```

Fall back to `gcx`:

```bash
gcx datasources list -o json
```

Record the UIDs and types. Subsequent queries need them.

If neither `mcp-grafana` nor `gcx` is configured for the user's
Grafana instance, pause and ask them to authenticate one of them
before continuing.

## Step 2: ask the user for service labels

Read the user's `runbook.md` from elicitation. If they recorded
`service labels`, use them. If not, ask:

> "What label and value identify your service in Prometheus? For
> example, some teams use `service_name="my-app"`, others use
> `service="my-app"` or `job="my-app"`. Please tell me the exact
> key and value."

Confirm by running a smoke query:

```promql
up{<label_key>="<label_value>"}
```

If `up` returns no series, the label is wrong. Ask again or use
`mcp-grafana`'s label discovery:

```
list_label_names(datasource_uid=...)
list_label_values(datasource_uid=..., label="service_name")
```

## Step 3: identify the k6 run window

For every load test run, you have:

- A start timestamp (from the k6 invocation).
- An end timestamp (from the k6 summary).
- A workflow name (`tests/wN-<short-name>/`).
- A test type (`smoke` / `average` / `stress` / …).
- An LG monitor CSV with per-second samples.

**Use those exact timestamps** as the `from` / `to` parameters in
every Grafana query. Don't query "last 1h" — that includes time
before and after the test, which contaminates the signal.

## Step 4: correlate signals

For each k6 threshold that failed, find the corresponding backend
signal.

### 4a. RED metrics (rate / errors / duration)

```promql
# Request rate
sum by (route) (
  rate(<your-http-request-counter>{<label>="<value>"}[1m])
)

# Error rate
sum by (route) (
  rate(<your-http-request-counter>{<label>="<value>",status=~"5.."}[1m])
) /
sum by (route) (
  rate(<your-http-request-counter>{<label>="<value>"}[1m])
)

# Latency p95
histogram_quantile(0.95,
  sum by (route, le) (
    rate(<your-http-request-duration-bucket>{<label>="<value>"}[1m])
  )
)
```

Generic metric name placeholders shown — replace with the
actual metric names from the customer's Prom. Discover them with:

```bash
gcx metrics query -d <prom-uid> 'group by (__name__) ({<label>="<value>"})' -o json
```

### 4b. Error logs

```logql
{<label>="<value>"} |= "error" | line_format ...
```

Filter by the k6 run window (`from` / `to`).

If the customer uses structured logging (JSON or logfmt), parse:

```logql
{<label>="<value>"} | json | level="error"
```

### 4c. Traces (if Tempo is configured)

```bash
# Find slow traces in the window
gcx traces query -d <tempo-uid> \
  --query '{service.name="<value>" && duration > 1s}' \
  --start <iso> --end <iso>
```

A representative trace from the slow window often explains *which*
downstream call is the bottleneck.

### 4d. Profiles (if Pyroscope is configured)

This is the high-value signal for CPU-bound bottlenecks. Be
careful to scope to the run window only:

```bash
gcx pyroscope query-profile -d <pyro-uid> \
  --query '<profile-type>{<label>="<value>"}' \
  --from <iso> --to <iso>
```

Look at the top frames. **Do not** assume what they mean — just
report them. The customer's engineers know their codebase; you
don't.

## Step 4½: verify absence before reporting it

A claim that a datasource has no data in the test window is a **strong claim**
that often drives architectural recommendations. Before making it, run **all
three** of these checks. If any one disagrees, you have a query bug, not data
absence:

1. **Label endpoint sanity check.** Run `gcx <product> labels -d <uid>` (or
   `-l <key>` for a specific label) for the datasource. If the label endpoint
   returns *any* values for the relevant key (e.g. `resource.service.name`
   returns the service), the datasource has indexed data — your *query* is
   what's wrong, not the datasource.
2. **Raw response, not parsed.** Re-run the same query **without** any `--json
   <field>` filter and read the raw output. `gcx --json <field>` extracts a
   specific top-level field; if you guessed the wrong field name, you'll get
   `{"<field>": null}` and mistake it for emptiness. The hint `gcx` prints on
   every call (`use --json list to discover fields, --json field1,field2 to
   select`) is your prompt to do this. Discover fields first, filter after.
3. **Wider window.** Re-run with a window 10× as long (e.g. `--from now-24h`).
   If still empty, the datasource is plausibly empty; if data appears, you had
   a clock-skew, retention-edge, or time-zone bug.

Only after **all three** confirm absence is the finding "no data in datasource
X" valid. Otherwise the finding is "my query returned no results", which is
not the same thing. **Never** report a tracing / profile / log gap without
running these checks.

If both `gcx` and `mcp-grafana` are installed, an optional fourth check is to
re-run the same query through the other tool. Two independent JSON shapes
can't both be wrong the same way.

### Failure case to remember

In a past run of this skill the agent ran
`gcx traces query ... --json data` and got `{"data": null}` back. It treated
that as "Tempo has no traces" and wrote a finding labelled "tracing pipeline
silently broken". In reality the response field is `traces`, not `data`;
Tempo had full coverage and a representative slow trace would have pinpointed
the bottleneck root cause one level deeper than Pyroscope alone could. The
agent had already queried the label endpoint and received non-empty results
(check 1 above), which contradicted the absence claim — but didn't notice.
Don't let that happen again.

## Step 5: hand back specific evidence

Bad finding:

> "The backend was slow during stress."

Good finding:

> "During the stress test of W3 (2026-05-13 22:14-22:30 UTC), the
> `recommend` endpoint's p95 latency rose from 120ms at baseline
> to 1.4s at peak load. Correlating with Pyroscope (link), the
> top frame consumed 53% of CPU samples in the window. Customer
> engineers should investigate whether this code path can be
> optimised or moved off the hot loop."

Every finding gets:

- The k6 run identifier and window.
- The specific metric or log query (so the customer can reproduce).
- A Grafana panel link if a relevant dashboard exists.
- A neutral observation, not a fix recommendation.

## Tool selection (gcx vs mcp-grafana)

- **In-session, structured, single query:** prefer `mcp-grafana`.
- **Multiple queries scripted in shell, multi-context, CI:** prefer
  `gcx`.
- **Tempo trace selectors:** mcp-grafana has richer selector
  support.

Both are acceptable. Don't argue with the user's preferred tool.

## When the customer doesn't own the backend

Skip this entire workflow. The report should explicitly state:

> "Backend-side investigation was not performed because the
> customer does not own the backend. Findings are limited to
> what k6 can observe from the client side: response status,
> latency, body, and Web Vitals."

This is a perfectly valid outcome. Don't fabricate backend
findings from client-side signals.
