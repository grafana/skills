# Building functional tests

Per workflow, you produce two functional tests:

- **`protocol.js`** — single-iteration, single-VU, hand-cleaned from
  `from-har.js`. Uses `expect()` for hard assertions.
- **`browser.js`** — single-iteration, single-VU, hand-converted
  from the Playwright recorder. Uses `expect()` for hard assertions.

Both must pass via `./tests/run-all.sh` **before any load test runs**.

## Contents

- [`protocol.js` — cleaning `from-har.js`](#protocoljs-cleaning-from-harjs)
  - Step 1: Move `User-Agent` to `options.userAgent`
  - Step 2: Rename the group
  - Step 3: Parameterise the base URL
  - Step 4: Replace recorded credentials with test credentials
    - [Cookies, CSRF, and k6's CookieJar API](#cookies-csrf-and-k6s-cookiejar-api) — `r.cookies` vs `r.json()`; `jar:` vs `cookies:` footgun
  - Step 5: Drop the auto-inserted `sleep(1)`
  - Step 6: Add `expect()` on every load-bearing response
  - [Why hard assertions in functional tests but `check()` in load tests](#why-hard-assertions-in-functional-tests-but-check-in-load-tests)
- [`browser.js` — 5-step Playwright → k6/browser conversion](#browserjs-5-step-conversion-from-playwright-recorder)
  - Step 1: Replace imports
  - Step 2: Replace launch/context setup with `browser.newPage()`
  - Step 3: Keep the page-interaction body verbatim
  - Step 4: Replace `expect` (Playwright) with k6-testing `expect`
  - [Step 4.5: `newPage()` vs `newContext().newPage()`](#step-45-newpage-vs-newcontextnewpage) — when to reach for context-level control
  - Step 5: Wrap in `try / finally`
- [Running functional tests](#running-functional-tests)
- [What "passing" means](#what-passing-means)

## protocol.js: cleaning `from-har.js`

`har-to-k6` produces a verbatim transcript of the HAR. It is not
suitable as a maintainable test. Apply these cleanups:

### 1. Move `User-Agent` to `options.userAgent`

`har-to-k6` sets `User-Agent`, `sec-ch-ua`, `sec-ch-ua-mobile`,
`sec-ch-ua-platform` on every request. Drop them; set the UA once:

```js
const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';

export const options = {
  vus: 1,
  iterations: 1,
  userAgent: USER_AGENT,
};
```

The UA must be a **real Chrome** string. Headless UAs trigger
bot-blocking.

### 2. Rename the group

har-to-k6 names the group from the HAR's `_pageref`, which is opaque
(`page_0`, `page_1`, …). Replace with a descriptive name:

```js
group('w1-login-then-purchase', function () { /* ... */ });
```

### 3. Parameterise the base URL

```js
const BASE_URL = __ENV.BASE_URL || 'https://target-host.example';
```

Replace every absolute URL in `from-har.js` with
``${BASE_URL}/path``.

### 4. Replace recorded credentials with test credentials

If the HAR contains a session cookie or bearer token, replace it
with:

- A well-known test token (e.g. `__ENV.TEST_TOKEN`).
- Or a login step at the top of the iteration body.

**Do not commit recorded credentials.** The HAR captures the live
session; treat it like a secret. The cleanup step is where this
data becomes safe to commit.

#### Cookies, CSRF, and k6's CookieJar API

k6 has two distinct cookie surfaces that are easy to confuse. Get
them wrong and your authenticated workflow looks like it works
but actually replays no session at all.

**Reading cookies the server *set***: response cookies are on the
`r.cookies` object, keyed by name, valued as an array of cookie
records. A common CSRF pattern is the server returning an empty
body but setting a `csrf_token` cookie:

```js
// WRONG — reads from JSON body, which is empty.
const r = http.post(`${BASE_URL}/api/csrf-token`);
const csrf = r.json('csrf_token');     // undefined

// RIGHT — read the Set-Cookie value.
const r = http.post(`${BASE_URL}/api/csrf-token`);
const csrf = r.cookies.csrf_token && r.cookies.csrf_token[0].value;
```

**Storing cookies across requests** (login → authenticated requests):

By default k6 maintains a **per-VU global cookie jar**, automatically.
For a normal logged-in workflow you don't need to do anything — just
hit `POST /login`, then make subsequent requests on the same VU, and
the session cookie is carried.

If you do need an explicit jar (e.g. multiple parallel users in one
VU), the per-request option name is `jar:`, not `cookies:`:

```js
// WRONG — `cookies` expects a name→value object, not a jar. k6 ignores
// the jar here, so the request silently uses the default per-VU jar.
const jar = new http.CookieJar();
http.get(url, { cookies: jar });

// RIGHT — use jar:, or just rely on the default per-VU jar.
const jar = new http.CookieJar();
http.get(url, { jar });
```

**Sending a CSRF token** that arrived via cookie:

```js
http.post(`${BASE_URL}/api/rate`, body, {
  headers: {
    'Content-Type': 'application/json',
    'X-CSRF-Token': csrf,        // pulled from r.cookies.csrf_token[0].value
  },
});
```

Verify the contract works in your `protocol.js` smoke run before
trusting it under load — silent CSRF-missing 403s are a classic way
to discover the issue only on stress day.

### 5. Drop the auto-inserted `sleep(1)`

har-to-k6 adds `sleep(1)` at the end of the iteration. Functional
tests are single-iteration; remove it.

### 6. Add `expect()` on every load-bearing response

```js
import { expect } from 'https://jslib.k6.io/k6-testing/0.5.0/index.js';

// Status assertion on every static asset (so a hash-renamed bundle
// after a rebuild fails the test loudly rather than silently 404):
for (const [kind, path] of assets) {
  const res = http.get(`${BASE_URL}${path}`, { /* ... */ });
  expect(res.status, `asset ${path}`).toBe(200);
}

// Body-shape assertion on the load-bearing response:
expect(res.status).toBe(200);
const data = res.json('result');
expect(data).not.toBeNull();
expect(typeof data.id).toBe('string');
expect(data.id.length).toBeGreaterThan(0);
```

Rule of thumb: every `http.*` call gets at least a status
`expect()`. The response that carries the workflow's payload gets
additional body-shape assertions.

### Why hard assertions in functional tests but `check()` in load tests

| Functional test                          | Load test                          |
|------------------------------------------|------------------------------------|
| `expect()` aborts iteration on failure   | `check()` records a metric        |
| Single iteration → abort = failed test   | Many iterations → don't poison run |
| Used to validate the script is correct   | Used to measure under load         |

In the load script you'll also add `tags: { name: 'EndpointName' }`
to each request for per-endpoint thresholds (see
`slo-design.md`).

## browser.js: 5-step conversion from Playwright recorder

The body of the Playwright recorder is the body of the
`k6/browser` default function, modulo framework scaffolding.

### Step 1: Replace imports

```js
// Recorder:
const { chromium } = require('playwright');

// k6/browser:
import { browser } from 'k6/browser';
import { expect } from 'https://jslib.k6.io/k6-testing/0.5.0/index.js';
```

### Step 2: Replace launch / context setup with `browser.newPage()`

```js
// Recorder:
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ /* ... */ });
const page = await context.newPage();

// k6/browser:
export const options = {
  scenarios: {
    wN_<short_name>: {
      executor: 'shared-iterations',
      vus: 1, iterations: 1,
      options: { browser: { type: 'chromium' } },
    },
  },
};

export default async function () {
  const page = await browser.newPage();
  try {
    // ... body ...
  } finally {
    await page.close();
  }
}
```

### Step 3: Keep the page-interaction body verbatim

The Playwright `page.*` API is the same in k6/browser. `page.goto`,
`page.locator`, `page.waitForResponse`, `Promise.all(...)`, all
work identically.

The hydration-signal wait you used in the recorder transfers
verbatim — keep it.

### Step 4: Replace `expect` (Playwright) with k6-testing `expect`

```js
// Recorder (Playwright):
import { expect } from '@playwright/test';
await expect(button).toBeVisible();

// k6/browser:
import { expect } from 'https://jslib.k6.io/k6-testing/0.5.0/index.js';
await expect(button).toBeVisible();
```

The k6-testing `expect()` API is a deliberate subset of Playwright's
`expect()` — most assertions transfer 1:1. `toBeVisible`,
`toContainText`, `toHaveText`, `toBeEnabled`, etc. all work.

### Step 4.5: `newPage()` vs `newContext().newPage()`

The templates use `browser.newPage()` because it's the right default
for **stateless** iterations — each iteration gets a fresh page, and
k6 does NOT share cookies between iterations of the same VU when you
call `browser.newPage()`. For 99% of workflow tests this is what you
want.

Use `browser.newContext()` first if your test specifically needs:

- A custom user agent or locale per iteration that overrides the
  global `options.userAgent`.
- Cookies preloaded into the browser before navigation (e.g. testing
  a partially-authenticated state without going through the login UI).
- Explicit cookie *isolation* in a scenario that creates multiple
  pages per iteration — `newContext()` is the boundary in that case.

```js
// Default (recommended):
const page = await browser.newPage();

// Only when you need context-level control:
const context = await browser.newContext({ userAgent: '...', locale: 'en-GB' });
const page = await context.newPage();
try {
  // ...
} finally {
  await page.close();
  await context.close();   // also close the context
}
```

Don't reach for `newContext()` "just to be safe" — it adds complexity
and the cleanup ordering matters. Stick with `newPage()` unless one of
the cases above applies.

### Step 5: Wrap in `try / finally`

```js
export default async function () {
  const page = await browser.newPage();
  try {
    // ... body ...
  } finally {
    await page.close();   // always close the page; resource leak otherwise
  }
}
```

In the load-test versions (e.g. `smoke.js`, `average.js`), the
wrapper expands to `try / catch / finally` with an
`iteration_completed` Rate — see `slo-design.md`.

## Running functional tests

```bash
# All workflows, both kinds:
./tests/run-all.sh

# Just one:
k6 run tests/wN-<short-name>/protocol.js
K6_BROWSER_HEADLESS=true k6 run tests/wN-<short-name>/browser.js
```

`run-all.sh` writes per-test logs to `${TMPDIR}/k6-run-all/` so a
failure can be drilled in.

Exit code = failure count. Treat any non-zero exit as
"do not proceed to load testing".

## What "passing" means

For protocol tests: every `expect()` resolves true. k6 prints
`✓ all checks passed`. Exit code 0.

For browser tests: same, plus the test ran headless without
crashing the chromium process. If k6 reports the iteration
"interrupted", investigate before treating the test as flaky.
