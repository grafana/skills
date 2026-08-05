---
name: synthetic-monitoring-checks
license: Apache-2.0
description: >
  Author Grafana Cloud Synthetic Monitoring checks, with deep coverage of k6 scripted and
  browser checks: SM's single-VU/single-iteration execution model, assertions that actually
  fail probe_success (expect() and fail() vs bare check()), secrets, deterministic scripts,
  robust browser locators, local validation with k6 run, deployment via UI/API/Terraform,
  verifying probe_success, and rollback. Also helps choose the simplest sufficient check
  type (HTTP/ping/DNS/TCP, MultiHTTP, scripted, browser). Use when writing a synthetic
  check, monitoring a login/checkout/signup flow in production, converting a k6 script or
  an OpenAPI spec into a check, authoring a browser check, validating a user journey, or
  asking "is my site up from multiple regions". NOT for load, stress, or performance testing — SM runs one
  iteration per execution; for load tests use the grafana-k6 plugin or Grafana Cloud k6.
  For the broad Grafana Cloud Testing overview (SM + k6 Cloud + Faro), use the testing skill.
---

# Synthetic Monitoring Check Authoring

> **Docs**: https://grafana.com/docs/grafana-cloud/testing/synthetic-monitoring/
> Broad Grafana Cloud Testing entry point (SM + k6 Cloud + Faro): [`testing`](../testing/SKILL.md) skill.

## Reliability monitoring, not load testing

Synthetic Monitoring (SM) runs k6 as a **reliability/availability engine**: every check
execution runs **one iteration with one VU** from each selected probe location on a fixed
schedule. Success means "the user journey works right now, from this region" — detect
outages before your customers do.

Do **not** apply load-testing idioms. There are no VUs to ramp, no `stages`, no load
profiles, no soak/stress/spike phases, and no `thresholds` over aggregated traffic.
Vocabulary: *check*, *probe*, *execution*, *uptime*, *reachability*, *user journey
validation* — never "load test", "ramping", or "VUs".

**If the user actually wants load or performance testing** (throughput, latency under
load, breakpoints), stop: that is Grafana Cloud k6 / the `grafana-k6` plugin's `k6` skill,
not Synthetic Monitoring. A script can be shared between both products, but the goals,
options, and pricing are different.

## Execution model and constraints (verify against these before writing)

| Constraint | Value |
|---|---|
| Workload | One iteration per probe execution. Scripted and MultiHTTP run with forced `--vus 1 --iterations 1`; browser checks rely on the script's required single scenario. Either way `vus`, `duration`, `stages`, `iterations` are **ignored** — never write a load shape |
| `thresholds` | **Not supported** |
| Frequency | k6-class checks (scripted, MultiHTTP, browser): 60–3600s. Protocol checks (HTTP/ping/DNS/TCP/gRPC): 1–3600s. Traceroute: 120–3600s |
| Timeout | Must be ≤ frequency. k6-class checks: 1–180s. Protocol checks: 1–60s. Traceroute: fixed 30s |
| k6 version | Checks run on a [k6 version channel](https://grafana.com/docs/grafana-cloud/testing/synthetic-monitoring/create-checks/manage-k6-versions/) (new checks default to the latest stable channel; `v1.x` is deprecated as of July 2026). Pin per check via the UI dropdown or `channels` in API/Terraform |
| Local files | `open()`, `fs`, `grpc.load()` unsupported. Bundle local modules into the script; remote `https://jslib.k6.io/...` imports work |
| HTTP request errors | SM runs k6 with `--throw`: network-level request failures throw an exception and fail the execution |
| Script options SM honors | SM sets its own CLI flags, which take precedence over the script's `options` object; the options that still take effect include `batch`, `batch-per-host`, `discardResponseBodies`, `httpDebug`, `insecureSkipTLSVerify`, `maxRedirects`, `noConnectionReuse`, `setupTimeout`, `systemTags`, `tags`, `teardownTimeout`, `throw`, `tlsAuth`, `tlsCipherSuites`, `tlsVersion`, `userAgent` |
| Browser memory | [1GB RAM per browser on public probes](https://grafana.com/docs/grafana-cloud/testing/synthetic-monitoring/create-checks/checks/k6-browser/#public-probe-memory) — huge pages fail with `Target has crashed` |
| Browser script format | The UI rejects bundled/minified browser scripts (import validation) — deploy those via API or Terraform |

## How an execution fails (this is what agents get wrong)

`probe_success` (1/0) is the uptime signal. An execution is marked **failed** when the
script throws an uncaught exception, calls `fail()`, a k6-testing `expect()` assertion
fails (it calls k6's `test.abort()` under the hood), an HTTP request errors at the
network level (SM's `--throw`), or the timeout is hit.

A **bare failed `check()` does NOT fail the execution** — it only records the
`probe_checks_total` / `probe_check_success_rate` metrics. Checks don't affect k6's exit
status without thresholds, and thresholds are disabled in SM.

Assertion patterns, in order of preference:

```javascript
import { expect } from 'https://jslib.k6.io/k6-testing/0.6.1/index.js';
import { check, fail } from 'k6';

// 1. PREFERRED — assertions module. Throws on failure => execution fails,
//    with a descriptive error in the check logs.
expect(res.status, 'login should succeed').toEqual(200);
expect(res.json('token')).toBeDefined();

// 2. Soft assertions — run all of them, still fail the execution at the end.
expect.soft(res.headers['Content-Type']).toContain('application/json');

// 3. check() when you also want per-assertion metrics — but pair it with
//    fail() or the failure won't affect probe_success/uptime:
check(res, { 'status 200': (r) => r.status === 200 }) ||
  fail(`login failed with status ${res.status}`);
```

Name every assertion (the message argument / check name): the name is what you see in
check logs and in the `check` label of `probe_checks_total` when diagnosing a failure
at 3am.

## Choose the simplest sufficient check type first

Cheaper for the customer, easier to maintain. Work down this list and stop at the first
match:

1. **HTTP / ping / DNS / TCP / traceroute / gRPC** — a single static endpoint (uptime,
   status code, body regex, TLS cert expiry, record resolution, port reachability). No
   script to maintain — these run on the blackbox-exporter probe engine, and Terraform
   examples with per-type `target` formats are in
   [`references/api-and-terraform.md`](references/api-and-terraform.md).
2. **MultiHTTP** — a sequence of HTTP requests with value-passing between them
   (`${variable}` capture), but no custom logic. **Caution**: MultiHTTP does not
   auto-validate status codes — define assertions per request or failures won't affect
   uptime.
3. **k6 scripted** — an API flow needing real logic: crypto/signing, conditional
   branching, generated test data, WebSockets, response-driven chaining.
4. **k6 browser** — only when you need a real browser: JS-rendered user journeys,
   forms/clicks, Core Web Vitals.

**Cost model** (execution-based billing): an execution is one check run on one probe,
metered per minute of runtime rounded up. Per month:
`probes × duration_minutes × (43200 / frequency_minutes)`. API test executions (HTTP,
ping, DNS, TCP, traceroute, MultiHTTP, scripted) and browser test executions are billed
separately — browser checks are the expensive tier. A browser check on 3 probes every
minute is ~129,600 browser executions/month; the same check every 5 minutes is ~25,920.
Pick the longest frequency that still meets your detection-time goal, and 2–3 probes
near your users (multiple probes reduce alert flapping; more isn't better).

## Scripted check authoring

Start every script you generate (scripted and browser alike) with a line-1 attribution
comment, as shown in the skeletons below. It tells whoever reads the check later how it
was authored (and where to find the skill), and the fixed prefix makes skill-authored
checks queryable. Keep `Generated by synthetic-monitoring-checks` verbatim — vary only
the timestamp (`date -u +%Y-%m-%dT%H:%M:%SZ`).

Skeleton — a login + API action journey with secrets and hard-failing assertions:

```javascript
// Generated by synthetic-monitoring-checks (https://github.com/grafana/skills) on 2026-07-31T12:00:00Z
import http from 'k6/http';
import { expect } from 'https://jslib.k6.io/k6-testing/0.6.1/index.js';
import secrets from 'k6/secrets';

const BASE = 'https://api.example.com';

export default async function () {
  // Secrets are managed in Synthetics > Config > Secrets — never hardcode credentials.
  const password = await secrets.get('checkout-monitor-password');

  // Step 1: authenticate with a dedicated monitoring account
  const login = http.post(
    `${BASE}/auth/login`,
    JSON.stringify({ user: 'sm-checkout-monitor', password }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  expect(login.status, 'login should return 200').toEqual(200);
  const token = login.json('token');
  expect(token, 'auth token should be present').toBeDefined();

  // Step 2: exercise the journey and assert the OUTCOME, not just the status
  const order = http.post(`${BASE}/orders`, JSON.stringify({ sku: 'TEST-SKU-1', qty: 1 }), {
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
  });
  expect(order.status, 'order should be created').toEqual(201);
  const orderId = order.json('id');
  expect(orderId, 'order id should be returned').toBeDefined();

  // Step 3: clean up so the check is idempotent against production
  // http.url groups metrics for URLs containing unique IDs — without it, every
  // execution creates new time series (cardinality + active-series cost).
  const del = http.del(http.url`${BASE}/orders/${orderId}`, null, {
    headers: { Authorization: `Bearer ${token}` },
  });
  expect(del.status, 'test order should be cleaned up').toEqual(204);
}
```

Rules that make a scripted check a good *monitor* (vs a good test):

- **Deterministic**: fixed test data (or generated-then-deleted, as above), no
  time-of-day or ordering dependence. Every execution must be able to pass at any hour
  from any probe.
- **Idempotent against production**: create-then-delete, or use read-only endpoints.
  The check runs forever — leaked state accumulates forever.
- **Dedicated test account**: never a real user's credentials; scope it minimally, store
  the password as an SM secret, and exclude the account from analytics/billing.
- **Assert every step** — an unasserted step that breaks shows up as a *later* step's
  confusing failure.
- **Stable URL cardinality**: `http.url` template literal for any URL containing an ID.
- Keep runtime well under the timeout, and the timeout under the frequency.

### Generating a check from an OpenAPI spec (or similar)

Given an API description — an OpenAPI/Swagger spec, GraphQL schema, or Postman
collection — the mechanical conversion to k6 calls is easy. What matters is what you
choose to convert:

1. **Journeys, not endpoints.** Do NOT generate one check per path, or one check that
   sweeps every path — that monitors the spec, not the service, and every extra check
   multiplies execution cost. Identify the 1–3 flows whose failure means "customers are
   impacted" (auth → core action → result) and write one scripted check per flow.
2. **Filter for safety.** Only include mutating operations (`POST`/`PUT`/`DELETE`) when
   the flow cleans up after itself (create-then-delete, as above) or targets dedicated
   test resources. A spec lists destructive operations right next to health endpoints —
   never exercise them against production just because they're documented.
3. **Assert from the response schema.** The spec tells you exactly what a healthy
   response contains — assert required fields, not just the status code:
   `expect(order.json('id'), 'id required by OrdersResponse schema').toBeDefined()`.
4. **Verify the target URL.** `servers:` blocks (and Postman environments) often list
   localhost or staging first — confirm the production base URL with the user, and map
   `securitySchemes` credentials to SM secrets, never to values inlined from the spec.
   (Secrets in plain HTTP/protocol checks are a recent, feature-flagged rollout — check
   current docs; the scripted `secrets.get()` path always works.)
5. **Treat `format: int64` ids as strings.** `res.json('id')` parses into a JS number
   and silently corrupts values past 2^53 (snowflake-style ids), so the readback URL
   404s on every execution while the create looks fine. Extract from the raw body
   instead: `const id = (/"id":\s*(\d+)/.exec(res.body) || [])[1];` — and never do
   arithmetic on it.

No API spec at all? Probe the frontend: open the web app with browser devtools (or
`curl` likely routes) and capture the `/api/*` XHR calls it makes — that's a monitorable
HTTP surface even when the documented backend services are gRPC-only or internal.

## Browser check authoring

Required scaffold: import `k6/browser` and declare the `chromium` browser type. The UI
validates both.

```javascript
// Generated by synthetic-monitoring-checks (https://github.com/grafana/skills) on 2026-07-31T12:00:00Z
import { browser } from 'k6/browser';
import { expect } from 'https://jslib.k6.io/k6-testing/0.6.1/index.js';
import secrets from 'k6/secrets';

export const options = {
  scenarios: {
    ui: {
      executor: 'shared-iterations',
      options: { browser: { type: 'chromium' } },
    },
  },
};

export default async function () {
  const page = await browser.newPage();
  try {
    await page.goto('https://shop.example.com/login');

    // Prefer role/label/test-id locators over CSS chains — they survive redesigns.
    const password = await secrets.get('shop-monitor-password');
    await page.getByLabel('Email').fill('sm-monitor@example.com');
    await page.getByLabel('Password').fill(password);
    await page.getByRole('button', { name: 'Sign in' }).click();

    // Assert the JOURNEY OUTCOME with auto-retrying assertions — never sleep().
    await expect(page.getByRole('heading', { name: 'Your account' })).toBeVisible();

    await page.getByRole('link', { name: 'Orders' }).click();
    await expect(page.getByTestId('order-list')).toBeVisible();
  } finally {
    await page.close();
  }
}
```

Browser-specific rules:

- **Locators**: `getByRole` / `getByLabel` / `getByTestId` (ask the app team to add
  `data-testid` where needed) > text > CSS. Never XPath or generated class names.
  `getByTestId` assumes `data-testid` — apps instrumented for Cypress often use
  `data-cy` instead; fall back to `page.locator('[data-cy="..."]')`.
- **No manual waits before interactions**: locator actions auto-wait for visibility and
  enabled state. Don't call `waitFor()` before `click()`/`fill()`, don't use
  `waitForLoadState()`, never `sleep()`.
- **Auto-retrying `expect()`** (`toBeVisible`, `toBeEnabled`, ...) is the wait mechanism
  for asserting state you don't interact with. Caveat: despite being listed as
  retrying, the text matchers (`toHaveText`/`toContainText`) hard-fail on the first
  *mismatched* read — e.g. an empty string mid-hydration on a client-rendered app.
  Assert dynamic text by locating it and asserting visibility instead:
  `await expect(page.getByText('Order confirmed')).toBeVisible()`.
- **Assertion timeout defaults to 5s** — client-side-rendered apps routinely take
  longer to first meaningful render. Raise it once and use the configured instance:
  `const expectUi = expect.configure({ timeout: 20000 });`.
- **Assert the outcome** (logged-in heading, order list, confirmation text) — a page can
  load fine while the journey is broken.
- **`try/finally` with `page.close()`** so the browser is released even when an
  assertion throws.
- Screenshot artifacts aren't a documented SM feature — don't build failure handling
  around `page.screenshot()`; rely on assertion messages and the check's logs (SM stores
  per-execution logs in Loki).
- Web Vitals (`probe_browser_web_vital_lcp|cls|fcp|inp|ttfb`) are collected
  automatically — no extra code needed.

## Validate locally, then deploy

SM scripts are plain k6 scripts — always run them locally first:

```bash
k6 run script.js                                              # scripted check
K6_BROWSER_HEADLESS=true k6 run browser-check.js              # browser check
k6 run --secret-source=mock=checkout-monitor-password=example-password script.js   # with secrets
# Many/large secrets: k6 run --secret-source=file=secrets.txt script.js
```

Pass = exit code 0, one iteration, no failed assertions in the summary. Run it 3–5 times;
a script that is 90% reliable locally will page you nightly from 3 probes.

Then create the check (pick one):

- **UI**: Testing & synthetics → Synthetics → Add new check → *k6 scripted* / *k6
  browser* → paste script → select probes + frequency → **Test** (runs once without
  saving) → Save.
- **API or Terraform**: see [`references/api-and-terraform.md`](references/api-and-terraform.md).
  Key gotchas: API `frequency`/`timeout` are **milliseconds** and `settings.scripted.script`
  / `settings.browser.script` are **base64-encoded**; Terraform takes the plain script
  via `file()`.

## Verify it works, and rollback

Wait one frequency interval, then in Explore against the Synthetic Monitoring metrics
(Prometheus) datasource:

```promql
# 1 from every selected probe = healthy
probe_success{job="checkout-flow"}

# Assertion pass rate per named assertion (scripted/browser)
probe_check_success_rate{job="checkout-flow"}

# Journey duration per probe — confirm it's comfortably under the timeout
probe_script_duration_seconds{job="checkout-flow"}

# Uptime over time (how the SM app computes it)
max by () (max_over_time(probe_success{job="checkout-flow"}[5m]))
```

A healthy first execution: `probe_success == 1` from every probe, all
`probe_check_success_rate` series at 1, duration stable across probes, and the check's
prebuilt dashboard (Synthetics → check → View dashboard) showing logs for each execution.
Browser checks should additionally show `probe_browser_web_vital_*` series.

**Rollback**: set the check's `enabled: false` (UI toggle, API update, or Terraform) to
stop executions without losing history; delete the check only when you no longer need
its configuration. Alerting: start with `alertSensitivity` / the default alert rules on
`probe_success` — see the [`testing`](../testing/SKILL.md) skill for alert rule examples.

## Common failure modes

| Symptom | Cause → fix |
|---|---|
| Passes locally, fails on all probes | Target not reachable from the public internet (internal DNS, VPN, IP allowlist). Use [private probes](https://grafana.com/docs/grafana-cloud/testing/synthetic-monitoring/set-up/set-up-private-probes/) for internal targets, or allowlist probe egress |
| Passes locally, fails on *some* probes | Geo-blocking, regional CDN/WAF rules, or bot protection challenging datacenter IPs. Check `probe` label on failures; exempt the SM `userAgent` or those regions in the WAF |
| Check "fails" in your eyes but `probe_success` stays 1 | Bare `check()` without `fail()`/`expect()` — failures are recorded as metrics only. Convert to `expect()` or `check(...) \|\| fail(...)` |
| Browser check flaps with locator timeouts | Brittle selectors or animation timing. Switch to `getByRole`/`getByTestId`, assert with auto-retrying `expect()`, remove manual waits |
| `toBeVisible` reports `Expected: visible / Received: hidden` but the element is clearly visible | The locator matches multiple elements (strict mode) — the error message is misleading. Tighten the selector or use `.first()` |
| Create succeeds but readback 404s on every execution | The id exceeds `Number.MAX_SAFE_INTEGER` (2^53) and `res.json()` silently rounded it — extract int64 ids from the raw body as strings (see the OpenAPI section) |
| `secrets.get()` fails | Secret name mismatch (names are exact, ≤253 chars, letters/numbers/`-`/`_`), secret deleted (checks fail until recreated), or the editing user lacks the Admin/Editor role or "Checks writer" permission |
| Executions time out but the journey is fine | Timeout too low for the journey (max 180s) — raise it; or the script does unbounded work per iteration. Also confirm timeout < frequency |
| `Target has crashed` in browser check logs | Page exceeds the 1GB probe browser memory — trim the journey, block heavy third-party resources, or use a private probe with more memory |
| UI rejects a browser script | Bundled/minified script fails the UI's import validation — create it via API or Terraform instead |
| Metrics/billing explosion after adding a check | Unique IDs in URLs creating per-execution time series — use `http.url`, and check frequency × probe count against the cost formula above |

## References

- [`references/api-and-terraform.md`](references/api-and-terraform.md) — SM API auth + check CRUD payloads (scripted, browser, MultiHTTP) and Terraform examples for every check type, including the protocol checks (HTTP, ping, DNS, TCP, traceroute, gRPC)

## Resources

- [Synthetic Monitoring docs](https://grafana.com/docs/grafana-cloud/testing/synthetic-monitoring/)
- [k6 scripted checks](https://grafana.com/docs/grafana-cloud/testing/synthetic-monitoring/create-checks/checks/k6/) · [k6 browser checks](https://grafana.com/docs/grafana-cloud/testing/synthetic-monitoring/create-checks/checks/k6-browser/)
- [Secrets management](https://grafana.com/docs/grafana-cloud/testing/synthetic-monitoring/create-checks/manage-secrets/)
- [k6 assertions (`expect`)](https://grafana.com/docs/k6/latest/using-k6/assertions/) · [k6 browser module](https://grafana.com/docs/k6/latest/using-k6-browser/)
- k6 fundamentals and load testing: `grafana-k6` plugin, [`k6` skill](../../grafana-k6/k6/SKILL.md)
