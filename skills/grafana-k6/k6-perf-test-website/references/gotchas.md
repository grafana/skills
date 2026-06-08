# Generic gotchas

Things this skill has learned the hard way. All non-app-specific.
None of these are framework / language / database gotchas — those
are emergent findings, not assumptions.

## Recording / functional

### Third-party RUM and error reporters pollute HAR captures

Public websites typically embed third-party agents: RUM
(Real User Monitoring), error reporters, ad networks, analytics,
A/B test scripts, social-media widgets. Their requests:

- Inflate the HAR by 10-100×.
- Add unrelated endpoints to your per-endpoint threshold list.
- Cause k6 to send test traffic to third-party collectors (rude
  and may breach their TOS).

**Fix:** `recordHar.urlFilter` regex that allow-lists only the
target host(s). See `recording-with-playwright.md`.

### `HeadlessChrome` UA triggers bot-blocking

Many production sites filter the default headless UA at the WAF
or CDN level. Symptoms:

- 403 / 429 / 503 on the first request.
- Redirects to a bot-challenge page.
- Empty responses.

**Fix:** set `options.userAgent` to a real Chrome UA on every k6
script, and `browserContext({ userAgent: ... })` on every
Playwright recorder.

### Hydration timing breaks recorders

SPAs render some markup before client JS hydrates and attaches
event handlers. If the recorder clicks before hydration, the
click does nothing.

**Fix:** wait for a post-hydration sentinel locator (an interactive
element that only exists after the framework has booted). See
`recording-with-playwright.md`.

## SLO design

### `http_req_duration p(95) < 500` hides slow endpoints

The global threshold is dominated by the fastest, most-frequent
endpoints (static assets, small JSON). A slow critical endpoint
hides in the aggregate.

**Fix:** tag every protocol request with `tags: { name: '...' }`
and threshold per tag.

### `group()` does not work in async (browser) code

k6's `group()` does not measure awaited code reliably. The
group_duration metric will not capture what you intended.

**Fix:** use `performance.mark/measure` inside `page.evaluate()`
and record a custom Trend. See `slo-design.md`.

### Web Vitals thresholds may need loosening — but never silently

Some real apps have deterministic layout shifts (e.g. a widget that
re-renders once data loads) the team has accepted. If you raise
`browser_web_vital_cls` from `< 0.1` to `< 0.2` to make tests
pass, **report it**: which workflow, which selector, the
deterministic CLS value, and the customer's decision not to fix.

Silent loosening is the #1 way perf tests stop catching regressions.

### Functional tests use `expect()`; load tests use `check()` + tags

`expect()` aborts iteration on failure. That's right for functional
tests (single iteration, abort = failed test) but wrong for load
tests (many iterations, abort poisons the run).

`check()` records a metric (`checks` rate) and continues. Pair it
with `tags: { name: '...' }` on the underlying http call so failures
show up per-endpoint in the summary.

### Pick one `expect`/`check` library per workflow — don't mix

The templates ship `expect()` from **`k6-testing`** (a JS library
loaded over HTTPS — Jest-style: `expect(r.status).toBe(200)`) in
`protocol.js` and `browser.js`, and bare `check()` from `k6` in the
load-test files (`smoke.js`, `average.js`, ...).

The exact import URL the templates use is:

```js
import { expect } from 'https://jslib.k6.io/k6-testing/0.5.0/index.js';
```

**Do NOT replace this with any of the following — they look
similar but are different code and will break in stock k6:**

| Wrong import                                                       | Why it breaks                                                                                              |
|--------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------|
| `import { expect } from 'k6/x/expect'`                             | `k6/x/*` are xk6 extensions that must be compiled into a custom k6 binary. Stock k6 fails at provisioning. |
| `import { expect } from 'https://jslib.k6.io/k6chaijs/4.3.4.3/index.js'` | Different assertion style: `.to.equal()` chains. If you import this and use `.toBe()` syntax, every call TypeErrors. |
| `import { expect } from '@playwright/test'`                        | Playwright lib; doesn't exist in k6's runtime.                                                              |

When you adapt a template into a real workflow, **stay with the
library the template chose**. Mixing libraries inside the same
iteration produces silent test invalidation:

- Importing `expect` from `k6-testing` and then calling
  `.to.equal()` (Chai/k6chaijs syntax) throws
  `TypeError: Cannot read property 'equal' of undefined or null`
  on every iteration.
- k6 then registers **zero** `checks` for the iteration. The
  threshold `checks: ['rate>0.99']` passes with `rate=0.00%`
  (k6 treats an empty metric as non-violating).
- All check failures are masked. The smoke run appears green but
  the assertions never ran.

Rule: the import path determines the assertion API. `k6-testing` =
`.toBe()` / `.toContain()` / `.toEqual()`. `k6chaijs` =
`.to.equal()` / `.to.include()` / `.to.deep.equal()`. Don't
cross-import.

### Workflows with expected 4xx/5xx responses break the default `http_req_failed` threshold

Some workflows intentionally exercise the *failure* path — e.g.
"anonymous user tries to rate a pizza, expect 401", "request a
deleted resource, expect 404". k6 counts any 4xx/5xx as a failed
request by default, so a workflow that produces one expected 401
out of every 5 requests will sit at a 20% `http_req_failed` rate
and immediately blow the template's
`http_req_failed: ['rate<0.01']` threshold.

You have two correct fixes; pick one per workflow and **document
the choice** in `runbook.md`:

**Fix A — module-level: tell k6 the expected status is not a failure.**
This is the cleaner option when the failure path is part of the
contract:

```js
import http from 'k6/http';

// Treat HTTP 401 as a non-failure response for this workflow's
// anonymous-rate check; all other non-2xx still count as failed.
http.setResponseCallback(
  http.expectedStatuses({ min: 200, max: 299 }, 401),
);
```

**Fix B — per-request: tag the expected-failure call and threshold
its tag separately.** Useful when only one specific request is the
expected-failure case:

```js
http.post(`${BASE_URL}/api/rate`, body, {
  tags: { name: 'AnonRateExpected401', expectedNon2xx: 'true' },
});

// thresholds:
'http_req_failed{expectedNon2xx:true}': ['rate<1.0'],     // permits 100% failed
'http_req_failed{expectedNon2xx:!true}': ['rate<0.01'],   // 2xx-only requests stay at <1%
```

Do **not** "fix" this by relaxing the global `http_req_failed`
threshold from `rate<0.01` to `rate<0.25`. That hides real
failures elsewhere in the workflow.

## Load generation

### LG saturation masquerades as server slowness

A CPU-pegged laptop running k6 silently throttles its own request
rate. Symptoms: lower-than-expected RPS, higher-than-expected
latency, "iterations interrupted".

**Fix:** always run with `run-with-monitor.sh`. Treat WARNING
verdicts (sys_cpu_idle < 10%) as inconclusive runs.

### Browser VUs cost ~1 GB RSS each

Don't stack browser VUs to "drive more load". Use protocol VUs
for load; keep browser VUs at 1 per scenario as a Web Vitals
canary.

### Custom Trend metrics accumulate in k6 client memory

Long browser soaks (60+ minutes) show k6 RSS climbing on the LG.
This is **not necessarily a server-side leak** — k6 accumulates
every metric sample in memory for the run summary.

**Verify** against the backend's memory metrics before reporting
a leak. If backend memory is flat but k6 RSS climbs, the climb is
client-side metric accumulation.

### `${ARRAY[-1]}` is bash 4+; macOS ships bash 3.2

Negative-index array subscript syntax was added in bash 4. macOS
ships bash 3.2 for licensing reasons. Helper scripts that use
`${arr[-1]}` will fail on macOS with `bad array subscript`.

**Fix:** explicit index arithmetic:
```bash
LAST_INDEX=$(( ${#arr[@]} - 1 ))
last="${arr[$LAST_INDEX]}"
```

## Cloud k6

### Browser VU-hours cost 10× protocol VU-hours

A 70-minute soak with 10 protocol + 1 browser VU costs:
`(10 × 70/60) + (1 × 70/60 × 10) = 11.67 + 11.67 = 23.3 VUh`.
The single browser VU costs as much as all 10 protocol VUs.

Confirm with the user before running browser-heavy soaks in cloud.

### Local results may disagree with cloud results

Possible reasons (all legitimate):

- LG was saturated locally.
- Network path differs (CDN edge location).
- Cloud `cloud.distribution` spreads VUs geographically.
- IP allow-list / WAF treats cloud LG IPs differently.

Trust cloud for measurement, local for validation. Don't blend them.

### `k6 cloud login` failures

If `k6 cloud run` fails with authentication errors, the user
hasn't completed the Grafana Cloud k6 auth flow on this machine.
Don't try to fix it inside this skill — pause and ask them to
authenticate (typically `k6 cloud login`, or whatever their
organisation's auth process is) before retrying.

## Reporting

### Vague findings are useless

"Latency is high" is not a finding. "GetRecommendation p(95) hit
1.4s at iteration ~200; corresponded to LG WARNING verdict; see
log path X" is.

Every finding needs: a specific metric, a specific window, and a
specific evidence path (k6 summary log, LG CSV, Grafana panel).

### Don't fabricate backend findings from client-side signals

"The database is slow" cannot be concluded from k6 alone. You can
say "the recommend endpoint's response time is high" — that's a
client-side observable. "The database is slow" requires backend
investigation per §9 of SKILL.md.

### Don't recommend fixes

The customer's engineers know their code. The skill reports what
k6 observed and what Grafana shows. It does **not** recommend code
changes. Hand the evidence back and let the team decide.

## Process

### Always elicit workflows before scaffolding

Without explicit workflows, every later step is guesswork. The
elicitation step exists for this reason; skipping it produces
tests that measure the wrong thing.

### Don't proceed to load testing until functional tests pass

`./tests/run-all.sh` must exit 0. A failing functional test
means the script has a bug; running load against it produces
noise, not signal.

### One file per test type, not a dispatcher

Tempting to write `load.js` with `LOAD_TYPE=__ENV.LOAD_TYPE`.
Reject the temptation. Each file should read cleanly in isolation
during incident review. See `hybrid-load-design.md`.
