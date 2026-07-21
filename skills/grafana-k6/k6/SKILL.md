---
name: k6
license: Apache-2.0
description: Generate, validate, and review k6 test scripts — load, stress, spike, soak, smoke, breakpoint, functional, and protocol. Covers HTTP, WebSocket, gRPC, browser, all executors, thresholds, checks, custom metrics, the k6-testing library, k6 Cloud execution, and the xk6 extension ecosystem; uses the xk6-docs CLI (with grafana.com web fallback) for docs lookup and validates every script by running it. Use when writing, generating, validating, or debugging any k6 or load-test script (including plain-language asks like "load test this API" or "stress test my service"), choosing executors/scenarios, or setting thresholds. For end-to-end website performance suites use k6-perf-test-website; for documenting k6 itself use k6-docs.
---

# k6 Script Generation

> **Efficiency note:** This is a short linear recipe (read example → adapt → save → validate → review). A todo list would just mirror the headings without adding value, so skip the planning overhead and execute the steps directly.
>
> **Agent-agnostic:** The steps below describe capabilities, not specific tools. Where a step says "fetch a URL" or "write a file", use whatever your agent provides for that capability (e.g. a web-fetch tool, a file-write tool, or shell `curl`/`tee`).

---

## Step 1: Pick the right example file

Read only the file that matches the user's request. Examples provide structural scaffolding — the correct scaffold, option shapes, and import patterns.

| User needs | Read this file |
|-----------|---------------|
| HTTP REST, auth flow, batch requests | `examples/http.js` |
| HTML parsing with parseHTML, SharedArray | `examples/html.js` |
| WebSocket | `examples/websocket.js` |
| gRPC | `examples/grpc.js` |
| Browser automation | `examples/browser.js` |
| Browser + functional test / `expect()` / k6-testing | `examples/functional.js` (browser scenario) |
| Functional/integration tests, `expect()`, k6-testing | `examples/functional.js` |
| Custom metrics, execution module, handleSummary, per-vu-iterations | `examples/metrics.js` |
| Load patterns, all executors (ramping, arrival rate, per-VU, etc.) | `examples/executors.js` |
| Cloud run, `--local-execution`, `cloud` options | `examples/cloud.js` |
| Crypto (HMAC, MD5, SHA256) or encoding (base64) | `examples/crypto-encoding.js` |
| xk6-faker | `examples/ext-faker.js` |
| xk6-redis | `examples/ext-redis.js` |
| xk6-sql / sqlite3 / postgres | `examples/ext-sql.js` |
| xk6-exec | `examples/ext-exec.js` |
| xk6-dns | `examples/ext-dns.js` |
| xk6-tls | `examples/ext-tls.js` |
| xk6-tcp | `examples/ext-tcp.js` |
| xk6-crawler | `examples/ext-crawler.js` |

Example files live in the `examples/` directory alongside this `SKILL.md`.

**When the request matches multiple rows** (e.g. "browser" + "functional test"), prefer the row whose assertion style fits the intent. If the user says "functional test", "assert", "verify", or "expect", use `functional.js` even if the test involves a browser — it demonstrates `expect()` with auto-retrying browser matchers. Use `browser.js` for browser load/performance tests that don't emphasize correctness assertions.

---

## Step 2: Adapt the example

Use the loaded example as the starting point. Adapt it to the user's exact requirements:
- Change endpoints, VU counts, durations, thresholds
- Add or remove scenario steps
- Rename functions and variables to match the domain
- Every expression must be complete and runnable — no `{ ... }`, `// TODO`, or stubs
- **Match the request — don't over-build.** Implement exactly what was asked. Don't add custom request tags, extra `sleep()` calls, additional endpoints, or `options` the user didn't request. Unrequested complexity lowers quality and reduces adherence to the spec.

For multi-scenario scripts (browser + HTTP, cloud): use named `scenarios` with `exec` pointing to separate exported functions.

---

## Step 3: Fill gaps with docs (only if needed)

The example covers common patterns. Adapt from it directly. **Skip this step entirely** if the example provides everything you need.

**Only reach for docs if**:
- The user asks for an API or option not demonstrated in the example, **or**
- You are not confident about the exact signature, option name, or return type

When a gap exists, first establish the docs command (one-time per session).

The `k6 x docs` CLI renders content only when it detects a TTY. Since agents
run non-interactively, wrap every call with `script` to allocate a pseudo-TTY
and pipe the ANSI-stripped content to stdout:

```bash
# Detect OS once (macOS vs Linux have different `script` flags):
if [[ "$(uname -s)" == "Darwin" ]]; then
  DOCS_CMD="script -q /dev/null k6 x docs"
else
  DOCS_CMD="script -qc 'k6 x docs' /dev/null"
fi

# Verify it works — should print a topic list, NOT a "browse files" guide:
$DOCS_CMD 2>/dev/null | head -5
```

If the output still shows "k6 documentation is a directory of markdown files",
the TTY wrapper isn't working. Fall back to **web docs** under
`https://grafana.com/docs/k6/latest/` — fetch pages with whatever web-fetch
capability your agent has (a built-in fetch tool, or `curl` in a shell).

If `k6 x docs` fails outright (command not found, provisioning or 404 errors),
read `SETUP.md` — it covers auto-provisioning on k6 v1.7.0+ and the manual
xk6 build for older versions.

Then look up what you need:

```bash
$DOCS_CMD <path>              # e.g. javascript-api k6-http
$DOCS_CMD <path> --depth 2
$DOCS_CMD search <term>
```

Common CLI paths and the 2-call strategy are in `docs-guidance.md`.

**Do not use unpkg, @types/k6, or any npm type definition URLs.**

---

## Step 4: Save

Line 1 of every script must be a generated-by comment. Get the current UTC timestamp first (the file content depends on it, so this can't be parallelized with the write):

```bash
date -u +%Y-%m-%dT%H:%M:%SZ
```

Then include it as line 1:
```javascript
// Generated by grafana-k6 on 2026-03-25T22:02:20.203Z
```

Save to `k6/scripts/<descriptive-name>.js`. Use lowercase kebab-case filenames. If your file-write capability doesn't create parent directories automatically, `mkdir -p k6/scripts` first.

**The script file on disk is the deliverable** — always write it. Never end the task with the script shown only in chat: Steps 5–7 (validate, review, present) all require the file to exist at `k6/scripts/<name>.js`. If a write fails, retry it before continuing.

---

## Step 5: Validate

Match top-down — the first matching row wins:

| Script type | Command |
|------------|---------|
| Imports `k6/browser` | `k6 run k6/scripts/<name>.js` |
| Any `ramping-vus` or `*-arrival-rate` scenario | `k6 inspect k6/scripts/<name>.js` — a full run would execute the entire load profile against the target |
| Other named `executor:` blocks (short scenarios) | `k6 run k6/scripts/<name>.js` |
| Everything else (HTTP, WS, gRPC) | `k6 run --vus 1 --iterations 1 k6/scripts/<name>.js` |

**What counts as passing:** for functional and browser scripts, validation passes only when the exit code is 0 *and* the summary shows no failed checks or `expect()` errors — a script that completes with failing assertions is not validated. k6's error output names the exact locator or assertion that failed (and what it waited for); use it to fix the selector or logic. For load tests, exit code 0 is a pass, and a pure threshold breach under load (exit code 99) is acceptable.

If validation fails: read stderr, fix the root cause, retry up to **3 attempts**. After 3 failures, present the error and ask the user how to proceed (or, when running unattended, deliver the best attempt and clearly report the unresolved error).

---

## Step 6: Best-practices review

### General checks (all scripts)

Review the script against the rules below. The checklist is authoritative — only look up docs (`$DOCS_CMD best-practices` or `https://grafana.com/docs/k6/latest/using-k6/`) if you're uncertain about a specific rule.

- **`export const options` with realistic VUs/duration.** Default VUs/durations make the test meaningful out of the box.
- **Define `thresholds` for every load test.** Without thresholds the run can't fail in CI even when performance regresses, which defeats the point of running a load test. At minimum include `http_req_duration` and `http_req_failed` (or the protocol equivalent). Pure functional tests — single-iteration `expect()`-only scripts — can skip this.
- **Include `sleep()` in closed-model (VU-based) load tests.** `sleep()` represents user think time; without it, VUs hammer endpoints faster than any real user would, inflating throughput and crowding out the system under test. This applies to VU-based HTTP, WebSocket, gRPC, crypto, and extension scripts. **Open-model executors** (`constant-arrival-rate`, `ramping-arrival-rate`) already pace iterations to a target rate, so `sleep()` there is usually unnecessary — it only ties up VUs without changing the offered load. Browser scripts use `page.waitForTimeout()` instead; single-iteration functional tests and one-shot connectivity/demo scripts can skip it. In event-driven WebSocket scripts, put the `sleep()` inside the `close` handler (see `examples/websocket.js`) — sleeping in the main function body blocks the event loop before any messages arrive.
- **Assert every response.** **Browser scripts**: use `expect()` from k6-testing — it auto-retries against locators and replaces `waitFor()` + `isVisible()` + `check()` chains. If you need a metric-tracked `check()` inside an async browser function, the standard `check` from `k6` works fine **as long as the predicate is synchronous** — `await` the value first, then check it. Only reach for the k6-utils wrapper (`https://jslib.k6.io/k6-utils/1.5.0/index.js`) when the predicate itself must `await` something: a bare `async` predicate returns a Promise, which is always truthy, so the check silently passes. **HTTP/gRPC/WS scripts**: use `check()` for metric-tracked assertions, or `expect()` for functional tests. Silent failures are worse than loud ones.
- **Browser scripts:** wrap interactions in `try/finally` with `page.close()` in `finally`, so pages clean up even when assertions throw.
- **gRPC scripts:** wrap the iteration's calls in `try/finally` and call `client.close()` in the `finally` block, so the connection is released even when a check throws mid-iteration.
- **WebSocket scripts:** wrap `JSON.parse` of incoming messages in `try/catch` — servers can send non-JSON frames, and one bad frame shouldn't kill the VU.
- **No `let`/`var` at top level** — use `const`, since module-scope state is shared across VUs and mutability there is almost always a bug.
- **No deprecated imports** — use `k6/websockets` for WebSockets; both `k6/ws` and `k6/experimental/websockets` are deprecated.

### Load & breakpoint tests

- **Breakpoint tests: ramp *offered load*, not VUs.** Use an open-model executor (`ramping-arrival-rate`) so the request rate is independent of how slow the system gets; a closed model (`ramping-vus`) throttles itself as latency rises and masks the breaking point. Pair thresholds with `abortOnFail: true` and a short `delayAbortEval` so the run stops (and reports) once an SLO is crossed.
- **Track SLO-relevant custom metrics** for reporting: per-endpoint latency (`Trend`), an error `Rate`, and any domain counters — plus a `handleSummary` that surfaces p95/p99, throughput (req/s), and error rate. See `examples/executors.js` and `examples/metrics.js`.
- **Hybrid protocol + browser load tests:** wrap the browser flow in `try/catch` and record failures to a custom error metric instead of letting an `expect()` throw — a single flaky browser iteration must not abort a long protocol load run.

### Browser scripts — recommended practices

If the script imports `k6/browser`, read `browser-best-practices.md` and apply all checks. Fix issues and re-validate.

---

## Step 7: Present results

1. Full script with file path
2. Validation output
3. Best-practices notes (issues found, or "all checks passed")
4. Suggested run command

```bash
k6 run --vus 10 --duration 30s k6/scripts/api-load-test.js
k6 run k6/scripts/browser-test.js
k6 cloud run k6/scripts/cloud-test.js
k6 cloud run --local-execution k6/scripts/hybrid-test.js
./k6-with-faker run k6/scripts/faker-test.js
K6_BROWSER_HEADLESS=true k6 run k6/scripts/browser-test.js
```

## Step 8: Execute

If the user confirms, run the command.
