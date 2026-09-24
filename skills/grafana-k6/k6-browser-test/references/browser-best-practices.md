# Browser test recommended practices

Apply these to every `k6/browser` test. If unsure about a topic, look it up with
`k6 x docs` (see SKILL.md Step 5) or the web docs under
`https://grafana.com/docs/k6/latest/using-k6-browser/recommended-practices/`.

## Selector priority — use `getBy*`, grounded in exploration

Resolve every selector by exploring the live site (`references/explore.md`), then
pick the highest applicable option:

1. `getByRole('button', { name: 'Submit' })` — interactive elements (buttons,
   links, checkboxes). Most resilient; mirrors how users perceive the page.
2. `getByLabel('Username')` — form fields with an associated `<label>`.
3. `getByText('Rated!')` — static text content.
4. `getByPlaceholder('Search')` — inputs identified by placeholder.
5. `getByTestId('cart-badge')` — when a stable `data-testid` exists.
6. `page.locator('[data-test="cart-badge"]')` / `page.locator('input[name="login"]')`
   — CSS attribute fallback for stable hooks `getBy*` can't target.
7. `page.locator('div.foo > button').first()` — last resort, brittle, avoid.

Caveats learned from real sites:
- **`getByTestId` matches only `data-testid`.** A `data-test` (or any other
  attribute) needs `page.locator('[data-test="…"]')` — otherwise the locator
  waits for a `data-testid` that never appears and times out (~30s).
- **`getByRole('textbox')` often matches multiple inputs** (a text field and a
  search field — and in some k6 versions a `password` field too), which trips
  strict-mode ambiguity. Prefer `getByLabel`/`getByPlaceholder` for inputs, or
  disambiguate (below).
- **Inputs with no accessible name** (no label/placeholder/aria/id) are valid
  targets for `page.locator('input[name="login"]')` — that's `name` as a CSS
  hook, which is fine, and is different from misusing it as an accessible name
  inside `getByRole({ name })`, which you should not do.
- **Submit/button `<input>`s** name themselves via their `value` attribute — use
  `getByRole('button', { name: <value> })`.
- **Headings and status text** are best asserted with
  `getByRole('heading', { name })` (or `getByText`) — `getByRole` is not only for
  interactive elements.

### Disambiguating repeated matches

Lists, tables, and product grids produce many elements with the same name (six
"Add to cart", two "Toggle Todo"). A bare locator then matches all of them and
is ambiguous — narrow it:

```javascript
await page.getByRole('button', { name: 'Add to cart' }).first().click();
await page.getByRole('checkbox', { name: 'Toggle Todo' }).nth(1).click();
await page.getByTestId('inventory-item').filter({ hasText: 'Backpack' })
  .getByRole('button', { name: 'Add to cart' }).click();   // scope by container
```

`getByRole({ name })` matches **case-insensitively as a substring** by default,
so `{ name: 'Load testing' }` also matches "Software load testing". Add
`{ name: '…', exact: true }` to pin the exact string when a short name collides
with longer ones. Conversely, an accessible name can fold in extra descendant
text and so differ from the explorer's `text` (which is `textContent`) — if
`exact: true` unexpectedly times out, drop `exact` and use `.first()`.

## Navigation waits — `load`, not `networkidle`

```javascript
// ✅ reliable everywhere
await page.goto(url, { waitUntil: 'load' });

// ❌ times out on analytics/chat-heavy sites that never go idle
await page.goto(url, { waitUntil: 'networkidle' });
```

After navigation or a click, **interact directly** with the next element — the
locator's actionability checks handle the wait. Do not call
`waitForLoadState()`, and do not `waitFor()` before an interaction:

```javascript
// ✅ correct
await page.goto(url, { waitUntil: 'load' });
await page.getByLabel('Username').fill(__ENV.TEST_USERNAME);

// ❌ redundant / brittle
await page.goto(url);
await page.waitForLoadState('networkidle');
await page.getByRole('button', { name: 'Login' }).waitFor({ state: 'visible' });
await page.getByRole('button', { name: 'Login' }).click();
```

`waitFor()` is only for asserting a state you will NOT interact with (e.g. a
post-hydration sentinel, or "a toast appeared and disappeared").

**Clicks that navigate.** When a click triggers a full-page navigation (a classic
form POST, a server-rendered link), still just interact with / assert on the
first element you expect on the next page — `expect()` retries across the
navigation. You do NOT need `page.waitForNavigation()` or `Promise.all([...])`
wrappers.

**Submitting without a button.** Search bars, TodoMVC, and login-on-Enter forms
often have no submit button — submit by pressing Enter on the field:

```javascript
await page.getByPlaceholder('What needs to be done?').fill('buy milk');
await page.getByPlaceholder('What needs to be done?').press('Enter');
```

**Deep / animated SPA navigation** is the one exception to "no fixed waits." In
some apps a click is actionable and fires, but the SPA drops the resulting
navigation (an animated menu still expanding, a route swapped mid-click) or the
element you matched detaches as the previous view unmounts — auto-retry can't
recover a click that already "succeeded" on a stale view. If a click fires but
the URL/state doesn't change, add a short settle (or wait on a URL/sentinel):

```javascript
await page.waitForTimeout(1000);          // let an animated menu finish opening
await page.getByRole('link', { name: 'Checks' }).click();
```

## Consent / cookie banners

Real sites overlay consent dialogs that intercept the first click. Dismiss the
banner as the first action — but make it **best-effort**: the banner may be
absent (a bare `getByRole(...).click()` on a missing banner hangs ~30s before
failing), and consent buttons often carry a long `aria-label` ("Accept the use
of cookies…") that overrides the accessible name, so `getByRole({ name: 'Accept
all' })` never matches. Prefer visible text, and don't let a missing banner
abort the test:

```javascript
await page.goto(url, { waitUntil: 'load' });
try {
  await page.getByText('Accept all', { exact: true }).click({ timeout: 3000 });
} catch (e) {
  // no banner, or a different label — carry on
}
```

The explorer's `dismissConsent` helper already does this (clicks an
Accept/Agree/OK control by text if present); resolve the precise control during
exploration and mirror it here.

## Assertions — `expect()` from k6-testing, not `check()`

```javascript
import { expect } from 'https://jslib.k6.io/k6-testing/0.6.1/index.js';

// ✅ one line, auto-retries until it passes or times out
await expect(page.getByText('Our recommendation:')).toBeVisible();
await expect(page.getByTestId('cart-badge')).toHaveText('1');
await expect(page).toHaveTitle(/QuickPizza/);
```

Retrying matchers: `toBeVisible`, `toBeHidden`, `toBeEnabled`, `toBeChecked`,
`toHaveText`, `toContainText`, `toHaveValue`, `toHaveAttribute`, `toHaveTitle`.

For an element that should be **absent**, use `toBeHidden()` (it passes for
elements not in the DOM) — 0.6.1 has no `toHaveCount`. Scope absent-checks to
the component under test, and if a matcher on visible text unexpectedly reports
`Received: hidden`, the locator is matching a **hidden duplicate** — these and
other assertion-target traps are detailed in
[explore.md → Resolving assertion targets](explore.md).

`toHaveText` compares the element's full **normalized** text, including nested
inline children — `<span><strong>1</strong> item left</span>` matches
`toHaveText('1 item left')`. Use `toContainText` for a substring.

`expect()` retries for a **default 5s**. For content known to load slower (a
deliberate AJAX delay, a heavy dashboard), raise it per matcher —
`await expect(locator).toBeVisible({ timeout: 15000 })` — or globally with
`expect.configure({ timeout: 60000 })`.

Only use `check()` when the user explicitly wants metric-tracked checks in the
end-of-run summary (functional *or* load — not only under load) — and then import
the async-aware version from k6-utils. The standard `check` from `k6` never
awaits its predicates: an async predicate returns a Promise, a Promise is truthy,
and the check records a pass regardless of what the page shows:

```javascript
// ✅ awaits async predicates
import { check } from 'https://jslib.k6.io/k6-utils/1.6.0/index.js';

// ❌ async predicates always "pass" (unawaited Promise is truthy)
// import { check } from 'k6';
```

Unlike `expect()`, `check()` does **not** auto-retry. Read page state through a
locator inside the predicate (locator reads auto-wait for the element), or the
check can flake right after a click/navigation.

## Structure and cleanup

- **`try/finally` with `await page.close()`** in `finally` — pages leak
  otherwise, and a thrown assertion would skip cleanup.
- **Default export is `async`** for functional tests; load tests export the
  scenario `exec` function (also `async`).
- **No top-level `let`/`var`** — module scope is shared across VUs; use `const`.
- **Think time** in load tests uses `page.waitForTimeout(ms)`, not `sleep()`.
- **One page per iteration** via `browser.newPage()`; reach for
  `browser.newContext()` only when you need per-iteration cookies/UA isolation.

## Screenshots

Capture screenshots by default for visual evidence and debugging (omit only if
the user declines). k6 auto-creates the directory named in the `path`.

- **Functional tests:** shoot after each navigation / significant action and
  before each assertion, with unique numbered paths (`screenshots/01-home.png`,
  `02-after-login.png`, …). When an assertion immediately follows an action, that
  action's screenshot already documents the pre-assertion state — don't take a
  redundant second one.
- **Load tests:** do **not** screenshot every iteration — the files flood the
  disk and the capture latency biases the Web Vitals you're measuring. Gate to
  the first iteration for evidence, plus an on-failure shot:

  ```javascript
  import exec from 'k6/execution';
  const shoot = exec.scenario.iterationInTest === 0;
  if (shoot) await page.screenshot({ path: 'screenshots/load-01-home.png' });
  // in catch: `screenshots/load-fail-vu${exec.vu.idInTest}-iter${exec.scenario.iterationInTest}.png`
  ```
- Screenshots write to the load generator's local disk; they are not uploaded to
  k6 Cloud.

## Load-mode extras

- Keep browser VU counts modest — browser VUs are far heavier than protocol VUs.
- Add Core Web Vitals thresholds so the run can fail on regression, at the **75th
  percentile** (how CWV are officially graded):
  `browser_web_vital_lcp` (p75<2500), `browser_web_vital_inp` (p75<200),
  `browser_web_vital_cls` (p75<0.1). A user can choose a stricter percentile; a
  1-VU functional test has too few samples for a meaningful p75, so omit them there.
- Avoid high-cardinality tags on browser metrics (too-many-time-series errors).

## Validate

Run and judge results per **SKILL.md Step 7** — iteration completion +
`expect()` results, not `browser_http_req_failed`, and exit 0 alone is not a
pass.
