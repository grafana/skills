---
name: k6-manage
description: Interact with Grafana Cloud k6 (GCk6) — manage load tests, test runs, scripts, projects, schedules, env vars, fetch metrics or logs, and run scripts locally — using the `gcx` CLI (or direct curl when gcx is unavailable). Use this skill whenever the user mentions a k6 cloud test or run, asks to list/edit/create/start/abort k6 load tests, wants to fetch logs or metrics for a test run, manage k6 project limits or schedules, run a k6 script locally or via `k6 cloud run`, or needs to call any `/cloud/v6/`, `/cloud/v5/`, or k6-app Loki endpoint against a Grafana Cloud stack. Trigger even when the user doesn't explicitly say "gcx" or "API" — phrases like "why did my k6 test fail", "show me logs for run X", "bump VUh limit on project Y", or "update my k6 script" all qualify. 
---

# Grafana Cloud k6 — interaction reference

The default path is the `gcx` CLI. When gcx isn't installed, every
endpoint here is still reachable via direct curl against k6's public
hosts — see §1.2 for the auth-header and host-translation rules. Two
principles shape the rest:

- **gcx owns Grafana-side auth (when present).** It injects the right
  headers on every call, so you should not set auth headers yourself.
  The only header you ever set by hand is `X-K6TestRun-Id`, on Loki
  log queries (§4), browser screenshot/file fetches (§6), and Tempo
  trace queries (§7) — anything else gets overwritten or causes
  conflicts. In curl mode the auth headers are manual; see §1.2.
- **Reach for `gcx k6 ...` subcommands first.** They wrap the common
  paths with friendlier ergonomics and handle pagination. Discover
  what's available with `gcx help-tree k6` (and drill in further with
  `gcx help-tree k6 <subcommand>`); fall back to `gcx api` only when
  no subcommand exists for what you need.

---

## 1. Authentication

### 1.1 With gcx (default)

```bash
gcx login --context <ctx>                # one-time OAuth, browser flow
gcx --context <ctx> config check         # expect "✔ Connectivity: online"
```

Once a context is logged in, every `gcx api ...` and `gcx k6 ...` call
inherits its auth state. If a call returns *"Invalid or expired token —
run gcx login to refresh"*, the OAuth session has lapsed — re-run
`gcx login --context <ctx>`.

### 1.2 Without gcx — direct curl

Check `command -v gcx` first. If it's missing, every endpoint in this
skill is still reachable directly against k6's public hosts — three
things change versus the gcx examples elsewhere:

- **Auth headers are manual.** Set both on every call:
  - `Authorization: Bearer <k6_token>`
  - `X-Stack-ID: <int>`
- **Hosts replace the plugin proxy.**
  - REST (`/cloud/v6/...`, `/cloud/v5/...`, `/cloud-resources/v1/...`,
    `/insights/...`) → `https://api.k6.io`
  - Logs (Loki) and traces (Tempo) → `https://cloudlogs.k6.io`
- **No `/api/plugins/k6-app/resources/{cloud,logs,insights}` prefix.**
  Drop it; everything after that prefix in the gcx examples is the
  real k6 path. The doubled `cloud/cloud/` quirk from §2 collapses to
  a single `/cloud/` — the first one was just the proxy route.

#### Obtaining the credentials

Don't guess these — prompt the user once per session for:

1. **k6 API token** — long-lived bearer; the same value
   `gcx k6 auth token` would print when gcx is configured.
2. **Stack** — either the integer **stack ID** (used directly in
   `X-Stack-ID`) or a Grafana **stack URL** (e.g.
   `https://myorg.grafana.net`). If the user supplies a URL, resolve
   it to an ID once with `GET /cloud/v6/auth`, which takes the URL in
   the `X-Stack-Url` header and returns `{stack_id, default_project_id}`:

   ```bash
   STACK_ID=$(curl -sS https://api.k6.io/cloud/v6/auth \
     -H "Authorization: Bearer $K6_TOKEN" \
     -H "X-Stack-Url: $STACK_URL" \
     | jq -r '.stack_id')
   ```

   Cache the resolved ID for the session — every subsequent call
   needs it in `X-Stack-ID`. (Note: `/cloud/v6/auth` is the *only*
   endpoint that takes `X-Stack-Url` instead of `X-Stack-ID` — it's
   how you cross the gap from "user-known URL" to "API-required ID".)

#### Translation cheat-sheet

| gcx form (plugin proxy)                                                                  | curl form (direct)                                                       |
|------------------------------------------------------------------------------------------|--------------------------------------------------------------------------|
| `gcx api /api/plugins/k6-app/resources/cloud/cloud/v6/test_runs/123`                     | `curl https://api.k6.io/cloud/v6/test_runs/123 -H ...`                   |
| `gcx api /api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/<id>/metrics`            | `curl https://api.k6.io/cloud/v5/test_runs/<id>/metrics -H ...`          |
| `gcx api /api/plugins/k6-app/resources/cloud/cloud-resources/v1/files/index`             | `curl https://api.k6.io/cloud-resources/v1/files/index -H ...`           |
| `gcx api /api/plugins/k6-app/resources/insights/insights/api/v1/testrun/<id>/executions` | `curl https://api.k6.io/insights/api/v1/testrun/<id>/executions -H ...`  |
| `gcx api /api/plugins/k6-app/resources/logs/api/v1/query_range?...`                      | `curl https://cloudlogs.k6.io/api/v1/query_range?... -H ...`             |
| `gcx api /api/plugins/k6-app/resources/logs/api/v1/tempo/api/search?...`                 | `curl https://cloudlogs.k6.io/api/v1/tempo/api/search?... -H ...`        |

In every `-H ...` slot above, send both auth headers:
`-H "Authorization: Bearer $K6_TOKEN" -H "X-Stack-ID: $STACK_ID"`.

Notes:
- Endpoint-specific headers gcx leaves to you — `X-K6TestRun-Id` on
  log, trace, and files endpoints (§4, §6, §7) — are still required
  *in addition* to the auth pair.
- The `gcx api` flag quirks in §2 (spill envelope, `--json field`
  filtering, `-o` for output format) don't apply to curl. Use plain
  curl flags: `-o file` to save body, `--data-binary @file` for PUT
  payloads, `-w '%{http_code}'` for status code, etc.
- Pagination semantics (`$orderby`, `$top`, `$skip`, `@nextLink`
  from §3) are properties of the v6 endpoints themselves and work
  identically over curl. The `@nextLink` URL returned by the server
  is already an absolute `https://api.k6.io/...` URL — pass it back
  to curl unchanged; the plugin-proxy reshape in §3 isn't needed.

---

## 2. How `gcx api` paths are shaped

When no subcommand exists, fall back to `gcx api` against the Grafana
plugin-proxy routes:

- **REST API** (`/cloud/v6/`, `/cloud/v5/`) — prefix with
  `/api/plugins/k6-app/resources/cloud/<k6-path>`.
- **Logs (Loki)** — prefix with
  `/api/plugins/k6-app/resources/logs/<loki-path>`.

| k6 path                                   | gcx invocation                                                                    |
|-------------------------------------------|-----------------------------------------------------------------------------------|
| `/cloud/v6/test_runs/{id}`                | `gcx api /api/plugins/k6-app/resources/cloud/cloud/v6/test_runs/{id}`             |
| `/cloud/v5/test_runs/{id}/metrics`        | `gcx api /api/plugins/k6-app/resources/cloud/cloud/v5/test_runs/{id}/metrics`     |
| Loki `/api/v1/query_range?...`            | `gcx api /api/plugins/k6-app/resources/logs/api/v1/query_range?...`               |

Note the doubled `cloud/cloud/` in every REST path — the first `cloud`
is the proxy route, the second is k6's `/cloud/v{N}/` namespace.

### `gcx api` flag quirks

`gcx api` is not a curl clone — a few flags differ from what curl muscle
memory suggests:

- **Response body** is written to stdout. There is no `-o <file>` flag
  for saving the body; `-o` selects output *format* (`json`, `yaml`,
  `agents`). Use shell redirection (`> file`) or `$(...)` capture
  instead.
- **Request body** uses `-d <string>`, `-d @file`, or `-d @-` (stdin).
  There is no `--data-binary`; `-d @file` already preserves bytes.
- **Field selection without jq**: `--json field1,field2,...` returns
  only the listed fields, and `--json list` (or `--json '?'`)
  discovers what's available. Often cleaner than piping into jq for
  shallow extractions.
- **Stderr noise**: gcx prints a one-line `hint:` to stderr on most
  invocations. Pipelines into `jq` should redirect with `2>/dev/null`
  to avoid surprises.
- **Response headers** are not directly exposed by `gcx api`. When a
  branch in the workflow hinges on `Content-Type` (e.g. script GET in
  §5), inspect the downloaded body with `file <path>` instead.
- **Large responses spill to a temp file**, with stdout reduced to a
  wrapper envelope. The threshold is a few tens of KB, so even
  moderately-sized list endpoints trigger it. The envelope looks like
  this:
  ```json
  {"spilled_to":"/var/folders/.../gcx-results-<n>.json",
   "bytes":2365037,
   "preview_sample":["@nextLink","value"],
   "message":"Response too large for stdout..."}
  ```
  Naive `json.loads(stdout).get('value', [])` patterns silently return
  empty in this case — the envelope has no `value` key. Two reliable
  fixes:
  - **Pass `-o json`** to force inline output regardless of size
    (recommended for scripts that parse the body). The agent-mode
    default formatting is what triggers the spill; `-o json` opts out.
  - **Or detect the envelope and re-read from the spilled file**:
    ```python
    d = json.loads(stdout)
    if 'spilled_to' in d:
        d = json.load(open(d['spilled_to']))
    ```
  Either works; `-o json` is fewer lines.

- **The Grafana plugin proxy rewrites `Content-Type: multipart/...`
  to `application/json`.** `gcx api` itself forwards your
  `-H "Content-Type: ..."` header correctly (visible in
  `--log-http-payload` traces), but the upstream plugin proxy
  rewrites multipart Content-Types to JSON before they reach k6's
  API. The net effect: endpoints that require multipart bodies —
  notably `POST /cloud/v6/projects/{id}/load_tests` for test
  creation, which takes `name` + `script` as form parts — return
  `HTTP 415 "Unsupported media type \"application/json\""` no
  matter what header you set on the gcx side. Fall back to direct
  curl against `api.k6.io` (§1.2) for these endpoints —
  `curl -F name=... -F script=@...` builds the multipart body for
  you and bypasses the plugin proxy. Other Content-Type values
  (e.g. `application/octet-stream` for the script-update PUT in §5)
  are forwarded through the proxy unchanged.

---

## 3. Discovering and calling endpoints

`gcx k6` subcommands (see `gcx help-tree k6`) cover the common reads.
For everything else — mutations, niche reads, endpoints not surfaced as
subcommands — the k6 Cloud API surface is large and changes over time.
Rather than rely on a cheat-sheet that goes stale, discover the
operation you need from the OpenAPI spec at request time.

### Workflow

1. **Fetch the spec once per session** (it's large; cache to `/tmp`):

   ```bash
   gcx api /api/plugins/k6-app/resources/cloud/cloud/v6/openapi > /tmp/k6-openapi.json
   ```

2. **Index by `operationId` + `description` first** — this keeps the
   working payload small while you search:

   ```bash
   jq '[.paths | to_entries[] | .key as $p | .value | to_entries[]
        | {path: $p, method: .key,
           operationId: .value.operationId,
           description: .value.description}]' /tmp/k6-openapi.json
   ```

   Grep this for the action you need ("abort", "limits", "schedule", …).

3. **Pull the chosen operation's full schema** — parameters, request
   body, response — resolving any `$ref` indirections:

   ```bash
   jq '.paths["<path>"]["<method>"]' /tmp/k6-openapi.json
   # Then for each "$ref": "#/components/schemas/Foo":
   jq '.components.schemas.Foo' /tmp/k6-openapi.json
   ```

4. **Build the `gcx api` call** against the same path, prefixed per §2.
   Authorization is already injected by gcx — do not add it yourself.

### List requests

When the operation you're calling is a list endpoint, default to
**ordering by `created` descending** (newest first) and **paginating
by 20** — both via whatever query parameter names the OpenAPI schema
for that operation exposes. Names vary (`ordering=-created`,
`order_by=created.desc`, `sort=-created`, `limit=20`, `page_size=20`),
which is exactly why discovering them from the spec in step 3 matters.
Newest-first means the entries the user usually cares about land in
the first page; a page size of 20 keeps the response small enough to
summarise without burning context.

#### Full enumeration: paginating with `@nextLink`

When you need to enumerate *all* rows (not just the newest page), the
v6 list endpoints cap each response at **1000 rows** (the default
`$top`) and return an `@nextLink` field pointing at the next page.
**`gcx k6 runs list --limit 0` does NOT auto-follow** `@nextLink` and
defaults to ascending order — for tests with >1000 historical runs it
silently returns the **oldest** 1000, not the newest. The
practical effect: `(first/last_run)` summarised from this output can
be wildly stale (e.g. a daily-scheduled test that's been running for
years will show a `last_run` from ~3 years ago). Use `gcx api`
against the v6 endpoint with `$orderby=created desc` for the
newest-first slice, or loop on `@nextLink` until it's absent for full
enumeration.

The v6 list endpoints expose OData-style query parameters:

| Param      | Purpose                                                              |
|------------|----------------------------------------------------------------------|
| `$orderby` | Ordering — value must be `<field> <direction>` (e.g. `created desc`). The allowed fields are operation-specific; `created` is the common one. Default is ascending. |
| `$top`     | Page size, default 1000 (also the cap)                              |
| `$skip`    | Offset (`@nextLink` already encodes this for you)                   |
| `$count`   | Include total count in response                                     |

Two practical defaults for the loop: `$orderby=created desc` so the
first page contains the newest runs (most of the time the agent only
cares about those), and `-o json` to opt out of the spill envelope
(see §2) so the parsing is uniform across pages.

```python
import json, subprocess, urllib.parse

CTX = "<stack>"
TEST_ID = "<test_id>"
PROXY = "/api/plugins/k6-app/resources/cloud"

all_runs = []
# Start with newest first; -o json keeps the body inline for clean json.loads().
path = (
    f"{PROXY}/cloud/v6/load_tests/{TEST_ID}/test_runs"
    "?%24orderby=created%20desc&%24top=1000"
)
while path:
    r = subprocess.run(["gcx", "--context", CTX, "api", path, "-o", "json"],
                       capture_output=True, text=True, timeout=60)
    d = json.loads(r.stdout)
    all_runs.extend(d.get("value", []))
    nxt = d.get("@nextLink")
    if not nxt:
        path = None
        continue
    # @nextLink comes back as an absolute http://api.k6.io/... URL with
    # OData params already encoded ($skip, $top, $orderby). Reshape its
    # path+query into the plugin-proxy prefix:
    p = urllib.parse.urlparse(nxt)
    path = f"{PROXY}{p.path}" + (f"?{p.query}" if p.query else "")
```

Same pattern works for any v6 list endpoint that returns `@nextLink`,
not just `/test_runs`. If you only need the few most-recent items,
stop the loop after the first page — with `$orderby=created desc` that
page is already the newest 1000.

### Metrics

Time-series and aggregate metrics live on the **v5** API
(`/cloud/v5/...`) — Prometheus-like query semantics inside OData-style
URL function-calls (`query_range_k6(query='...',metric='...')`), not
captured by the v6 OpenAPI. The full endpoint reference, selector
syntax, query methods per metric type, and worked examples are inlined
in [`references/metrics.md`](references/metrics.md) — read that before
constructing a metrics query.

### Logs

See §4.

---

## 4. Logs (Loki via `gcx api`)

The plugin proxies Loki under `/api/plugins/k6-app/resources/logs/`. The
only header you supply by hand is `X-K6TestRun-Id`; gcx handles
authorization.

```bash
RUN_ID="<run_id>"

# Scope the log window to the run itself: `created` for start, `ended`
# for end. If `ended` is null the run is still in progress — fall back
# to "now". Use a wider hard-coded window only when the run object's
# timestamps don't fit what you're investigating.
RUN=$(gcx api /api/plugins/k6-app/resources/cloud/cloud/v6/test_runs/$RUN_ID 2>/dev/null)
# k6 emits sub-second precision (e.g. "...:58.984041Z"); jq's
# fromdateiso8601 only accepts whole seconds, so strip the fraction.
START=$(echo "$RUN" | jq -r '.created | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601')
END=$(echo "$RUN"   | jq -r 'if .ended then (.ended | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) else (now | floor) end')

QUERY=$(printf '{test_run_id="%s"}' "$RUN_ID" | jq -sRr @uri)

# Save the raw response to /tmp/ — log payloads can be large; streaming
# them inline burns context. Summarise from the file, then jq into
# specific entries only when needed.
gcx api "/api/plugins/k6-app/resources/logs/api/v1/query_range?query=${QUERY}&direction=backward&start=${START}&end=${END}&limit=1000" \
  -H "X-K6TestRun-Id: $RUN_ID" 2>/dev/null > /tmp/run_${RUN_ID}_logs.json

# Tight summary — counts and stream labels only:
jq '{status, streams: (.data.result | length),
     total_entries: ([.data.result[].values | length] | add),
     stream_labels: [.data.result[].stream]}' /tmp/run_${RUN_ID}_logs.json
```

Pull individual entries from `/tmp/run_${RUN_ID}_logs.json` as needed
(e.g. `jq '.data.result[].values[]' …`) rather than re-running the
query.

Every LogQL query **must** include the `{test_run_id="<run_id>"}` stream
selector — the plugin proxy partitions logs by run and rejects (or
returns nothing for) queries without it. Layer additional filters on
top of that selector:

- `{test_run_id="<run_id>"}` — everything
- `{test_run_id="<run_id>"} | level=~"(error|warn)"` — errors and warnings only
- `{test_run_id="<run_id>"} |= "specific text"` — substring filter

Direction & window tips:

- **Scope `start`/`end` to the run's `created`/`ended` fields**, not to
  wall-clock "last hour" — otherwise queries silently miss anything
  older than the window. The only reason to deviate is when you
  specifically want a different interval (e.g. surrounding context).
- `direction=forward` with `start = run.created` to find the *first* errors.
- `direction=backward` with `end = run.ended` (or now, if still running)
  to find the *most recent* output.
- Loki retention typically outlives k6's cascade-delete, so logs of a
  deleted child run may still be queryable for a while.

---

## 5. Editing a test script safely

### Two distinct script endpoints

There are two GET endpoints that return a k6 script body, and they are
not interchangeable:

| Endpoint                                    | What it returns                           | When to use                                            |
|---------------------------------------------|-------------------------------------------|--------------------------------------------------------|
| `/cloud/v6/load_tests/<test_id>/script`     | The **current** load-test script (mutable; supports PUT) | Editing the script; reading current state              |
| `/cloud/v6/test_runs/<run_id>/script`       | The script **snapshot bundled into a specific run** (read-only) | Investigating what a past run actually executed; diffing across versions |

The two can drift apart: if the load-test script is edited after a
run completes, that run's bundled snapshot stays frozen at what it
executed, while the load-test endpoint serves the new current version.
The bundled-snapshot endpoint is GET-only — you cannot mutate
historical bytes.

The safe-edit recipe below uses the load-test endpoint (the editable
one). For run-vs-run script diffs (e.g. "did the script change between
the last passing and first failing run?"), GET both runs'
`/test_runs/<id>/script` and diff them locally.

### Script body format

The script GET endpoint returns one of two shapes — always detect which
before assuming the format:

- **Single js/ts file**. The recipe below handles this case directly.
- **k6 tar archive** (plain tar or gzipped). A multi-file project
  bundle (entry script + imported modules + assets). To edit: extract
  the JS file, modify it, then use `k6 archive` to rebuild the
  archive from the modified JS. Do **not** manually repack with
  `tar` — the archive contains a `metadata.json` with parsed options
  (projectID, thresholds, scenarios) that `k6 archive` regenerates
  correctly from the script source. Manual repacking preserves stale
  metadata and causes runtime errors (e.g. projectID mismatch).

  ```bash
  # Edit a k6 tar archive
  tar -xf /tmp/script_body -C /tmp/extracted/   # extract
  # ... edit the JS file ...
  k6 archive /tmp/edited_script.js -O /tmp/new_archive.tar  # rebuild
  ```

`gcx api` doesn't expose response headers (see §2), so detect the shape
by inspecting the downloaded body with `file(1)`:

```bash
gcx api /api/plugins/k6-app/resources/cloud/cloud/v6/load_tests/$ID/script \
  > /tmp/script_body
file /tmp/script_body
# Expected output (examples):
#   ASCII text          → js/ts source
#   POSIX tar archive   → k6 tar bundle
#   gzip compressed data → gzipped tar bundle
```

The PUT body must be the raw script (or archive) bytes
(`application/octet-stream`). gcx forwards the request to k6 unchanged.

```bash
ID="<load_test_id>"

# 1. Pull current script (single-file js/ts case)
gcx api /api/plugins/k6-app/resources/cloud/cloud/v6/load_tests/$ID/script \
  > /tmp/script_current.js

# 2. Backup
cp /tmp/script_current.js /tmp/script_backup_$(date +%s).js

# 3. Edit → /tmp/script_new.js

# 4. Local parse-only sanity check
k6 inspect /tmp/script_new.js | head -20

# 5. 1-iteration smoke (edit IN-FILE; --iterations CLI flag breaks browser scenarios)
sed 's/iterations: [0-9]\+/iterations: 1/' /tmp/script_new.js > /tmp/script_1iter.js
k6 run --quiet /tmp/script_1iter.js   # exit 0 = pass, 99 = threshold fail

# 6. PUT — Content-Type must be application/octet-stream
gcx api /api/plugins/k6-app/resources/cloud/cloud/v6/load_tests/$ID/script \
  -X PUT \
  -H "Content-Type: application/octet-stream" \
  -d "@/tmp/script_new.js"

# 7. Verify by re-fetching and comparing sha256 — the two hashes MUST match.
#    Do not rely on the `updated` timestamp; it does not bump on script PUT.
gcx api /api/plugins/k6-app/resources/cloud/cloud/v6/load_tests/$ID/script \
  > /tmp/script_verify.js
shasum -a 256 /tmp/script_new.js /tmp/script_verify.js
```

If the PUT returns 415, double-check that `-H "Content-Type:
application/octet-stream"` made it through (some shell quoting mistakes
can drop it). Pass `-vvv` to `gcx api` for the request/response trace
when debugging.

---

## 6. Browser screenshots

Browser-module runs write screenshot PNGs to per-run S3 storage —
that's the only artifact type the files API surfaces today. They're
not exposed via `/cloud/v6/`; retrieval goes through a separate
`cloud-resources/v1/files/` plugin route in a two-step flow. Both
calls require the same `X-K6TestRun-Id` header used for log queries
(§4) — gcx still handles auth, but the run ID must be supplied by
hand or the endpoint rejects with HTTP 422.

```bash
RUN_ID="<run_id>"

# 1. Index — JSON array of screenshot paths owned by this run. Empty
#    array if the run took none (e.g. non-browser tests, or browser
#    runs that didn't call page.screenshot()).
gcx api /api/plugins/k6-app/resources/cloud/cloud-resources/v1/files/index \
  -H "X-K6TestRun-Id: $RUN_ID" -o json 2>/dev/null > /tmp/files_${RUN_ID}.json

# Each entry looks like:
#   "7542817/files/screenshots/screenshots/login-success.png"
# The doubled "screenshots/screenshots/" segment is real, not a typo —
# pass the path back unchanged to step 2.

# 2. Request pre-signed download URLs for the files you want. The
#    request body must be JSON; Content-Type matters.
FILES=$(jq -c '[.[] | {name: .}]' /tmp/files_${RUN_ID}.json)
PAYLOAD=$(jq -nc --argjson files "$FILES" \
  '{service:"aws_s3", operation:"download", files:$files}')

gcx api /api/plugins/k6-app/resources/cloud/cloud-resources/v1/files/generate-pre-signed-url \
  -X POST \
  -H "X-K6TestRun-Id: $RUN_ID" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" -o json 2>/dev/null > /tmp/presigned_${RUN_ID}.json

# 3. Download each pre-signed URL directly — they're plain S3 GETs, no
#    gcx and no auth header (the signature is in the URL). The URLs
#    are valid for 24h (X-Amz-Expires=86400); re-run step 2 if they
#    expire.
mkdir -p /tmp/run_${RUN_ID}_files
jq -r '.urls[] | [.name, .pre_signed_url] | @tsv' /tmp/presigned_${RUN_ID}.json |
  while IFS=$'\t' read -r NAME URL; do
    curl -sS -o "/tmp/run_${RUN_ID}_files/$(basename "$NAME")" "$URL"
  done
```

### Notes worth knowing

- **Index before signing.** `generate-pre-signed-url` does *not*
  validate that the file exists — it will happily mint a URL for any
  key, and the 404 only surfaces when you try to download (S3 returns
  `<Error><Code>NoSuchKey</Code>...`). Always derive the file list
  from `files/index`, not from a guess at the path shape.
- **Batch the sign request.** `files` is an array, so request all the
  URLs you need in one POST rather than one call per file — same
  24h expiry covers the whole batch.
- **Browser tests vs. protocol tests.** Only runs that called
  `page.screenshot()` have entries in the index; a pure protocol/HTTP
  run will return `[]`. Don't assume the index is non-empty.

---

## 7. Browser traces (Tempo via `gcx api`)

Browser-module runs emit OTel spans for every iteration, navigation,
locator click, screenshot, web-vital observation, etc. The plugin
proxies a Tempo backend under `/api/plugins/k6-app/resources/logs/`
(same prefix as Loki — see §4), and the same `X-K6TestRun-Id` header
is required on every call. Without it, both search and fetch return
HTTP 401 `"Test run ID missing"`.

Retrieval is a two-step flow: TraceQL search → fetch full trace by
ID. The full trace is large (≈100 KB on disk for a 120-span iteration
because `-o json` pretty-prints; ~50 KB compact), so the
join+summarise step is what keeps agent context lean.

```bash
RUN_ID="<run_id>"

# 1. Find the run's start/end window and pick the scenario name.
#    Same caveat as §4: strip the sub-second fraction before
#    fromdateiso8601, and fall back to "now" if the run is still
#    running. Add a small buffer because spans can land slightly
#    after the run object reports `ended`.
RUN=$(gcx api /api/plugins/k6-app/resources/cloud/cloud/v6/test_runs/$RUN_ID 2>/dev/null)
START=$(echo "$RUN" | jq -r '.created | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601')
END=$(  echo "$RUN" | jq -r 'if .ended then (.ended | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) else (now|floor) end')
START=$((START - 60))
END=$((END + 60))

SCENARIO="ui"  # whatever your scenario is named; check run.ui.exec / k6 script

# 2. Search for iteration root spans. TraceQL goes in `q`; URL-encode
#    it. `start`/`end` must be unix seconds — RFC3339 returns
#    HTTP 400 `invalid start: strconv.ParseUint`. limit=500 caps the
#    result, enough to cover several thousand iterations.
Q=$(printf '{ name = "iteration" && span.test.iteration.number >= 0 && span.test.vu >= 0 && span.test.scenario = "%s" }' "$SCENARIO")
QE=$(printf '%s' "$Q" | jq -sRr @uri)

gcx api "/api/plugins/k6-app/resources/logs/api/v1/tempo/api/search?start=${START}&end=${END}&q=${QE}&limit=500" \
  -H "X-K6TestRun-Id: $RUN_ID" -o json 2>/dev/null > /tmp/traces_${RUN_ID}.json

# Each entry has: traceID (32-char hex), rootServiceName ("k6"),
# rootTraceName ("iteration"), durationMs, startTimeUnixNano, and a
# spanSet preview of the iteration root span's attributes
# (test.iteration.number, test.vu, test.scenario).

# 3. Fetch a full trace. The response is OTLP-shaped:
#    { "batches": [ { "resource": {...}, "scopeSpans": [ { "spans": [...] } ] } ] }
TRACE_ID=$(jq -r '.traces[0].traceID' /tmp/traces_${RUN_ID}.json)
gcx api "/api/plugins/k6-app/resources/logs/api/v1/tempo/api/traces/$TRACE_ID" \
  -H "X-K6TestRun-Id: $RUN_ID" -o json 2>/dev/null > /tmp/trace_${TRACE_ID}.json
```

### Compact summary for an agent

The OTLP body for a single iteration can run ~100 KB pretty-printed.
Dumping it verbatim into context is wasteful — most of the useful
signal lives in the span-name distribution, the slowest individual
spans, and the web-vital ratings. The pipeline below collapses a
trace into ~1–2 KB of plain text:

```bash
jq -r '
  # OTel value envelope: pick by key presence, not //-chaining — jq's //
  # treats `false` as missing and would drop legitimate boolValue:false.
  def attrval:
    if   has("stringValue") then .stringValue
    elif has("intValue")    then .intValue
    elif has("boolValue")   then .boolValue
    elif has("doubleValue") then .doubleValue
    else null end;
  def attrs: [.attributes[] | {(.key): (.value | attrval)}] | add // {};
  def dur:   (((.endTimeUnixNano|tonumber) - (.startTimeUnixNano|tonumber)) / 1000000 | floor);

  [.batches[].scopeSpans[].spans[] | {name, dur: dur, a: attrs, status: (.status.code // "OK")}] as $spans

  | "── span-name rollup (count · total ms · max ms) ──",
    ([$spans[] | {name, dur}]
       | group_by(.name) | map({name: .[0].name, n: length,
                                t: (map(.dur)|add), m: (map(.dur)|max)})
       | sort_by(-.t)[]
       | "  \(.n|tostring|.+"      "|.[0:4])  \(.t|tostring|.+"        "|.[0:7])  \(.m|tostring|.+"      "|.[0:6])  \(.name)"),

    "\n── slowest spans (ms · name · navigation.url / page.goto.url) ──",
    ([$spans[] | select(.name != "iteration")] | sort_by(-.dur) | .[0:8][]
       | "  \(.dur|tostring|.+"        "|.[0:7])  \(.name)\(if .a["navigation.url"] // .a["page.goto.url"] then "  " + (.a["navigation.url"] // .a["page.goto.url"]) else "" end)"),

    "\n── web-vital ratings ──",
    ([$spans[] | select(.name == "web_vital")
       | {n: .a["web_vital.name"], v: .a["web_vital.value"], r: .a["web_vital.rating"]}]
       | group_by(.n) | map({name: .[0].n,
                             ratings: ([.[].r] | group_by(.) | map({(.[0]): length}) | add)})[]
       | "  \(.name)  \(.ratings)"),

    "\n── span errors ──",
    ([$spans[] | select(.status != "OK" and .status != null)] | length | "  count: \(.)")
' /tmp/trace_${TRACE_ID}.json
```

On a run like 7542817 the output is something like:

```
── span-name rollup (count · total ms · max ms) ──
  1     154552   154552  iteration
  37    153391   17746   navigation
  11    21778    5168    page.waitForNavigation
  ...

── slowest spans (ms · name · navigation.url / page.goto.url) ──
  17746    navigation  https://k6e2etests.grafana-dev.net/a/k6-app/projects
  14992    navigation  https://k6e2etests.grafana-dev.net/a/k6-app/projects/58195
  ...

── web-vital ratings ──
  LCP   {"poor":5,"needs-improvement":1}
  CLS   {"good":2}
  ...
```

Two paragraphs of text capture which navigations are slow, which
web vitals are regressing, and the overall span-name distribution
— enough to reason about browser performance without paging through
the OTLP tree.

### Notes worth knowing

- **Header is mandatory.** Both `/search` and `/traces/<id>` return
  HTTP 401 without `X-K6TestRun-Id`. The header scopes the query to
  the run's tenant.
- **`start`/`end` are unix seconds.** RFC3339 ISO strings get
  `HTTP 400 invalid start: strconv.ParseUint`. They're technically
  optional — search works without them — but providing a window
  matching the run's `created`/`ended` (plus ~60s buffer) keeps the
  query fast and avoids matching unrelated runs that share the
  scenario name.
- **TraceQL, not LogQL.** The `q` parameter uses TraceQL — span
  predicates are written as `span.<attribute>` and combined with
  `&&`. The suggested query filters iteration root spans for a
  specific scenario; broaden by dropping `test.scenario`, narrow by
  adding e.g. `span.test.vu = 3 && span.test.iteration.number = 5`
  to pinpoint a single iteration on a single VU.
- **Scenario names come from the run.** They're the *keys* of
  `.options.scenarios` on the run object —
  `gcx api /api/plugins/k6-app/resources/cloud/cloud/v6/test_runs/$RUN_ID
  --json options 2>/dev/null | jq -r '.options.scenarios | keys[]'`
  lists them. The default scenario is named `default`; browser tests
  often name it `ui`, `browser`, etc.
- **Span IDs in the OTLP body are base64.** The `traceID` in the
  search response is hex (the form `/traces/<id>` accepts); the
  inner `traceId`/`spanId`/`parentSpanId` fields inside the OTLP
  batch are base64-encoded bytes. Cross-correlate parent/child via
  `parentSpanId == spanId`, both in base64 — no need to decode.
- **Useful attribute keys** on browser-test spans: `navigation.url`,
  `page.goto.url`, `screenshot.path`, `web_vital.name`,
  `web_vital.value`, `web_vital.rating`, `test.scenario`, `test.vu`,
  `test.iteration.number`, `k6.test_run_id`. These are the ones
  worth surfacing in summaries; the OTel value envelope is
  `{stringValue|intValue|boolValue|doubleValue}` (the jq
  `attrval` helper above handles all four).

---

## 8. Cloud Insights (audit results for a run)

Cloud Insights runs heuristics against a finished test — checks for
high cardinality, web-vital regressions, missing thresholds,
overutilised load generators, and so on — and exposes the results
through a separate `/resources/insights/` plugin route (not
`/cloud/v{N}/`). gcx still handles auth; no extra header is needed.

Three calls produce the data, and the agent-useful output is a join
across two of them:

```bash
RUN_ID="<run_id>"
BASE="/api/plugins/k6-app/resources/insights/insights/api/v1/testrun/$RUN_ID"

# 1. List executions for the run, take the most recent. The response
#    is { "executions": [ {id, version}, ... ] } — NOT a bare array.
#    Pick the last entry; insights re-runs append, and the newest one
#    reflects the current set of audits/scores.
EXEC_ID=$(gcx api "$BASE/executions" -o json 2>/dev/null \
  | jq -r '.executions[-1].id')

# 2. Audit definitions (id, title, description, weight). ~15 items.
gcx api "$BASE/executions/$EXEC_ID/audits" -o json 2>/dev/null \
  > /tmp/insights_audits_${RUN_ID}.json

# 3. Audit results (audit_id, status, score, explanation, actions).
gcx api "$BASE/executions/$EXEC_ID/audits/results" -o json 2>/dev/null \
  > /tmp/insights_results_${RUN_ID}.json
```

Both responses use the same top-level key — `audits` — but the
*contents* differ: step 2 is the catalog of what each audit checks,
step 3 is what that audit found on this particular run. Cross-join
them via `result.audit_id == audit.id` (1:1 in practice).

### Joining into a compact, agent-readable summary

The raw audit + results JSON together is ~10 KB. Dumping both into
context just to read out three lines per audit is wasteful — do the
join in `jq` and emit a single tight block. The pipeline below is
the recommended shape:

```bash
jq -nr \
  --slurpfile a /tmp/insights_audits_${RUN_ID}.json \
  --slurpfile r /tmp/insights_results_${RUN_ID}.json '
  ($a[0].audits | INDEX(.id)) as $defs
  | $r[0].audits
  | map({
      title:         ($defs[.audit_id].title // "?"),
      description:   ($defs[.audit_id].description // ""),
      status:        .status,
      status_reason: .status_reason,
      score: (
        if .score == null            then "n/a"
        elif .score.type == "binary" then (if .score.value then "pass" else "fail" end)
        else (.score.value | tostring)
        end),
      explanation: (.explanation // "" | gsub("\n+"; " ") | .[0:300]),
      actions:     (.actions // [])
    })
  | .[]
  | "── \(.title) — score: \(.score)\(if .status == "failed" then " [audit did not run: \(.status_reason // "unknown")]" else "" end)\n  \(.description)\n  → \(.explanation)\(if (.actions|length) > 0 then "\n  actions:\n    - " + (.actions|join("\n    - ")) else "" end)\n"
'
```

For a 15-audit run this emits ~5 KB of plain text — title, score,
one-line description, one-line explanation, and any action items.
That's enough for the agent to reason about the test's health
without re-reading either JSON blob.

### Notes worth knowing

- **`status` ≠ verdict.** `status: "succeeded"` means *the audit
  executed*. The verdict lives in `score` (`binary` true/false, or
  `numeric` 0…1 where 1 is best). `status: "failed"` means the audit
  itself could not run (typically `status_reason: "missing data"` —
  e.g. the HTTP Spans audit on a non-tracing test); the `score` field
  is absent. Treat these as "no signal", not as failures.
- **Score thresholds vary per audit.** A `numeric` 0.94 might be
  fine for one audit and concerning for another — there's no global
  cutoff. The `explanation` is authoritative for what the score
  means; surface it verbatim rather than inventing a pass/fail rule.
- **`actions` is the actionable bit.** Only present when the audit
  has concrete recommendations (e.g. "Reduce the cardinality of the
  `url` label …"). When summarising a run for a user who's trying to
  improve it, lead with audits that have a non-empty `actions` array.
- **Pick the last execution, not the first.** `.executions[]` is in
  chronological order; re-runs append. Older executions reflect
  older audit logic and may have stale results.
- **Insights is a post-run analysis.** If the run hasn't finished
  (or never produced enough data for insights to compute), the
  executions list may be empty — bail out gracefully on
  `length == 0`.

---

## 9. Local k6 CLI (smoke tests and `k6 cloud run`)

The local `k6` CLI is the right tool for parse checks and 1-iteration
smoke runs before pushing to cloud:

```bash
k6 inspect script.js | head -20      # parse-only sanity
k6 run --quiet script.js             # run locally
```

For `k6 cloud run` (uploads + runs in cloud from your laptop), authenticate
`k6 cloud login` with the token and stack URL pulled from gcx — token
comes from `gcx k6 auth token`, stack URL from the active gcx context's
`grafana.server` field:

```bash
TOKEN=$(gcx --context <ctx> k6 auth token)
STACK=$(gcx --context <ctx> config view --minify -o json | jq -r '.contexts[].grafana.server')
k6 cloud login --token "$TOKEN" --stack "$STACK"
k6 cloud run script.js
```

k6's cloud config (`~/.config/k6/cloud.json`) is single-context, so
re-run `k6 cloud login` whenever you switch gcx contexts — otherwise
`k6 cloud run` will keep targeting the previous stack.

Exit codes: `0` pass, `99` threshold fail, anything else = script/runtime error.

---

## 10. Gotchas

| Symptom                                                                              | Cause                                                                | Fix |
|--------------------------------------------------------------------------------------|----------------------------------------------------------------------|-----|
| `401 "Invalid or expired token — run gcx login to refresh"`                          | gcx OAuth session expired                                            | `gcx login --context <ctx>` |
| `403 / 404` on a path that looks right                                               | Forgot the doubled `cloud/cloud/` for a REST endpoint                | Use `…/resources/cloud/cloud/v{N}/…` |
| `415 unsupported media type` on script PUT                                           | Missing `-H "Content-Type: application/octet-stream"`                | Add it; pass `-vvv` (or `--log-http-payload`) to `gcx api` to inspect the request |
| Script PUT returns 200 but doesn't take effect                                       | `updated` timestamp does not bump on script change                   | Verify by sha256 of GET (§5 step 7) |
| Run status `passed` but checks failed                                                | Zero-observation thresholds report as pass; `check()` alone never fails a run | Add `'checks{check:<name>}': ['rate==1.0']`; in catch blocks, `check(null, {"script completed":()=>false})` to force an observation |
| Loki query returns nothing for a recent run                                          | `X-K6TestRun-Id` header missing                                      | Always pass `-H "X-K6TestRun-Id: <run_id>"` on log queries |
| `gcx k6 runs list --limit 0` returns the **oldest** 1000 rows, not the newest        | Subcommand doesn't follow `@nextLink` and defaults to ascending order — for >1000 runs the `first/last` you see are the start of the history, not the recent activity | Use `gcx api` with `$orderby=created desc` for a newest-first slice, or the full `@nextLink` loop in §3 |
| `gcx k6 load-tests update -f` returns `✔ Updated` but the change doesn't take effect | Fields outside the v6 PATCH schema (`PatchLoadTestApiModel` allows only `name`, `baseline_test_run_id` — `additionalProperties: false`) are silently dropped. Notably `project_id` is NOT updatable this way | For project moves use the dedicated `/move` endpoint (§11); for other mutations cross-check the PATCH schema in the OpenAPI spec. Always re-GET to confirm |
| `gcx k6 load-tests list --project-id <id>` returns tests from all projects           | The flag is accepted but never filters — `/cloud/v6/load_tests` has no project query param | Use `GET /cloud/v6/projects/{id}/load_tests` via `gcx api`, or filter client-side with `select(.project_id == X)` in jq |
| `HTTP 415 "Unsupported media type \"application/json\""` on a multipart POST through `gcx api` | The Grafana plugin proxy rewrites multipart Content-Types to `application/json` before forwarding (gcx itself sends the header you set; the proxy strips it) | Fall back to direct curl against `api.k6.io` (§1.2). Affects test creation (`POST /cloud/v6/projects/{id}/load_tests`) and any other multipart endpoint |
| `401 Unauthorized` calling `api.k6.io` / `cloudlogs.k6.io` directly (curl mode)      | Missing/wrong `Authorization: Bearer …` or `X-Stack-ID` header       | Re-check both headers; resolve `X-Stack-ID` from a stack URL via `/cloud/v6/auth` (§1.2) |
| `404` calling `api.k6.io/api/plugins/...` (curl mode)                                | Left the plugin-proxy prefix in by mistake                           | Strip `/api/plugins/k6-app/resources/{cloud,logs,insights}` — see §1.2 |

---

## 11. Mutations not covered by `update -f`

`gcx k6 <resource> update -f` follows the v6 PATCH schema for that
resource. Fields outside the schema are silently dropped while gcx
still prints `✔ Updated <resource> <id>` — see the §10 row. Several
common mutations have **dedicated endpoints instead**, and the PATCH
route will no-op on them.

| Mutation                              | Endpoint                                              | Body                          |
|---------------------------------------|-------------------------------------------------------|-------------------------------|
| Move test to another project          | `PUT /cloud/v6/load_tests/{id}/move`                  | `{"project_id": <int>}`       |
| Start a test run                      | `POST /cloud/v6/load_tests/{id}/start`                | `{}` (or run options)         |

**Polling a started run:** After starting a run, poll
`GET /cloud/v6/test_runs/{id}` until `status` reaches `completed` or
`aborted`. Always check the `result` field alongside `status` —
`status: completed` with `result: error` means a configuration or
infrastructure failure (not a threshold breach). On any non-`passed`
result, immediately fetch logs (§4) to surface the error rather than
waiting for the user to report it.

| Abort a running test                  | `POST /cloud/v6/test_runs/{id}/abort`                 | empty                         |
| Set / overwrite a schedule            | `POST /cloud/v6/load_tests/{id}/schedule`             | Schedule body (recurrence_rule or cron) |
| Deactivate / reactivate a schedule    | `POST /cloud/v6/schedules/{id}/{deactivate,activate}` | empty                         |
| Create a load test (multipart!)       | `POST /cloud/v6/projects/{id}/load_tests`             | multipart: `name` + `script`  |
| Persist a run past retention          | `POST /cloud/v6/test_runs/{id}/save`                  | empty (paired with `/unsave`) |

The PATCH-style updates that *do* work via `update -f`:

| Resource     | Updatable fields                                              |
|--------------|---------------------------------------------------------------|
| load test    | `name`, `baseline_test_run_id` (per `PatchLoadTestApiModel`)  |
| project      | `name` only (per `PatchProjectApiModel`)                      |

Both schemas declare `additionalProperties: false` — any other field
you put in the manifest is silently filtered out before the PATCH is
sent, even though gcx still reports `✔ Updated`. Don't try to flip
`is_default` or move a `grafana_folder_uid` through `update -f`;
they're not exposed for mutation on the v6 PATCH.

Cross-check by reading the operation's request schema in the OpenAPI
spec (workflow in §3) before assuming a field is mutable.

### Worked example — move a test between projects

```bash
gcx api /api/plugins/k6-app/resources/cloud/cloud/v6/load_tests/<test_id>/move \
  -X PUT \
  -H "Content-Type: application/json" \
  -d '{"project_id": <new_project_id>}'

# Verify — re-GET and check project_id reflects the new value.
# Do not trust the absence of an error from the PUT; HTTP 204 with
# empty body is the success shape but gcx api prints nothing.
gcx --context <ctx> k6 load-tests get <test_id> -o json | jq '{id, name, project_id}'
```

The OpenAPI description for this endpoint is explicit: *"Move a load
test to a different project of the same organization. All respective
test runs will be also moved to the new project."* You don't need to
migrate runs separately.

### Cascade behavior worth knowing

- **Deleting a load test cascade-deletes its schedule.** The schedule
  is gone from `/cloud/v6/schedules` and `/cloud/v6/load_tests/{id}/schedule`
  immediately. No need to `gcx k6 schedules delete <load-test-id>`
  first as a defensive step.
- **Deleting a project with a running test fails with HTTP 409**
  ("Cannot delete project with a running test." per the OpenAPI
  spec). Non-running tests appear to be removed with the project,
  but if you want to inventory a project's contents before deleting
  it, use `GET /cloud/v6/projects/{id}/load_tests` (NOT
  `gcx k6 load-tests list --project-id <id>`, which doesn't filter —
  see §10).
- **Moving a test moves its runs and run history with it.** Schedule
  attachment also follows the test (it's keyed by `load_test_id`,
  not by project).

### Verification rule of thumb

The recurring pattern in this skill is *"gcx confirms success even
when the underlying call no-ops"*. Whenever you mutate state:

1. Note what you expected to change (field, count, status).
2. Re-GET the resource and confirm the change is reflected.
3. If it isn't, check whether the mutation needed a dedicated
   endpoint (this section) rather than `update -f`.
