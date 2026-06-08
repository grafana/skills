# SLO design and threshold strategy

This skill's bundled templates use a four-layer threshold strategy:

1. **Global SLOs** — overall error rate + latency.
2. **Per-endpoint thresholds** — tag every protocol request,
   threshold per tag.
3. **Per-iteration thresholds** — the user-perceived workflow time.
4. **Web Vitals + custom action Trend** — page responsiveness under
   load.

This document explains the rationale for each layer and how to tune
them for the user's stated SLOs.

## Layer 1: Global SLOs

```js
http_req_failed: ['rate<0.01'],         // < 1% requests fail
http_req_duration: ['p(95)<500'],       // p95 across all requests < 500ms
checks: ['rate>0.99'],                  // > 99% of in-iteration checks pass
```

These are starting defaults. Tune to the user's Q6 answers from
the elicitation script. Common adjustments:

- Public website with heavy CDN: `http_req_duration p(95) < 300ms`.
- API gateway with downstream calls: `http_req_duration p(95) <
  800ms`.
- High-error-budget app: `http_req_failed rate < 0.05`.

## Layer 2: Per-endpoint thresholds

The global `http_req_duration p(95) < 500` is dominated by the
fastest, most-frequent endpoints (typically static assets and
small JSON endpoints). The slow, critical endpoints — the ones that
hurt users most — hide in the aggregate.

**Tag every protocol request:**

```js
http.get(`${BASE_URL}/api/recommend`, {
  tags: { name: 'GetRecommendation' },
});
http.post(`${BASE_URL}/api/order`, body, {
  tags: { name: 'CreateOrder' },
});
```

**Then threshold per tag:**

```js
thresholds: {
  // global SLOs
  http_req_failed: ['rate<0.01'],
  http_req_duration: ['p(95)<500'],
  checks: ['rate>0.99'],

  // per-endpoint
  'http_req_duration{name:GetRecommendation}': ['p(95)<1000', 'p(99)<1500'],
  'http_req_duration{name:CreateOrder}':       ['p(95)<800'],
  'http_req_duration{name:GetCatalogue}':      ['p(95)<400'],
  'http_req_duration{name:GetConfig}':         ['p(95)<300'],
},
```

Rule of thumb:

- One tag per business action that has its own SLO.
- Static assets and incidental fetches (images, fonts) do not need
  their own tag — they're already covered by the global threshold.
- Tag-name convention: `<HTTP-verb><Resource>` PascalCase, no
  hyphens, no slashes. `GetRecommendation`, not `get-/recommend`.

## Layer 3: Per-iteration thresholds

```js
'iteration_duration{scenario:browser}': ['p(95)<10000'],   // 10s end-to-end
```

This is the **user-perceived** workflow time. Set it to roughly
**2× the smoke median** of `iteration_duration{scenario:browser}`.
Smoke gives you a baseline; the load tests' p95 should stay near
the smoke median × 2 even under stress.

The skill recommends two iteration thresholds:

```js
'iteration_duration{scenario:browser}': ['p(95)<10000'],  // smoke + load
'iteration_completed{scenario:browser}': ['rate>0.99'],   // < 1% throws
```

`iteration_completed` is a custom Rate — see Layer 4 / async section.

## Layer 4: Web Vitals + custom action Trend

### Web Vitals (browser scenario only)

The skill restricts Web Vitals to **LCP, INP, CLS**:

```js
browser_web_vital_lcp: ['p(95)<2500'],
browser_web_vital_inp: ['p(95)<200'],
browser_web_vital_cls: ['p(95)<0.1'],
```

These are Google's "good" thresholds. The skill explicitly drops:

- **FCP** — superseded by LCP; rarely the first regression to fire.
- **TBT** — useful for lab synthetics but noisy under load.
- **TTFB** — measure server-side via `http_req_duration` instead.

**Loosening CLS for known accepted issues:** some real apps have a
deterministic layout shift (e.g. a ratings widget that re-renders
once data loads). If the team has chosen not to fix it, you may
raise the threshold to `< 0.2` — **but flag it in the report**.
Never silently raise a threshold.

### Custom action Trend (for the slow user action)

Web Vitals measure *initial render*. They miss post-click latency
for actions like "submit form", "compute recommendation", "load
next page". Add a custom Trend.

**In async (browser) code, `group()` does NOT work reliably.** k6's
`group()` does not wrap awaited code correctly; the group_duration
will not match what you intended. Use `performance.mark()` +
`performance.measure()` inside `page.evaluate()`:

```js
import { Trend } from 'k6/metrics';
const timeToResult = new Trend('time_to_result', true);

await page.evaluate(() => performance.mark('action-start'));
await Promise.all([
  page.waitForResponse(r => r.url().includes('/api/action')),
  button.click(),
]);
await resultLocator.waitFor({ state: 'visible' });

const ms = await page.evaluate(() => {
  performance.mark('action-end');
  return performance.measure('action', 'action-start', 'action-end').duration;
});
timeToResult.add(ms);
```

**Threshold:**

```js
time_to_result: ['p(95)<3000'],
```

**A threshold on a metric with zero samples passes vacuously.** If you
keep `time_to_result: ['p(95)<3000']` but never call `timeToResult.add()`
(the templates ship that call commented out), k6 reports the threshold
green while measuring nothing — the same empty-metric footgun described
for `checks` in `gotchas.md`. When you adapt a load template, either wire
up the `performance.mark`/`measure` block so the Trend gets samples, or
remove the threshold. Never ship it empty and trust the green.

### Custom Rate for browser iteration completion

Browser iterations throw on locator timeouts, evaluate errors,
network failures. Without instrumentation, those are invisible in
the threshold report (a thrown iteration is "interrupted" in k6's
summary, not "failed").

Wrap every browser iteration:

```js
import { Rate } from 'k6/metrics';
const iterationCompleted = new Rate('iteration_completed');

export async function browserIteration() {
  const page = await browser.newPage();
  let success = true;
  try {
    // ... workflow body ...
  } catch (e) {
    success = false;
    console.error(`browser iteration failed: ${e?.message || e}`);
    throw e;          // re-throw so k6 also marks iteration interrupted
  } finally {
    iterationCompleted.add(success);
    await page.close();
  }
}
```

**Threshold:**

```js
'iteration_completed{scenario:browser}': ['rate>0.99'],
```

## `group()` for sync (protocol) code

In **protocol** scenarios (synchronous, no `await`), `group()`
*does* work and produces a usable `group_duration` metric:

```js
import { group } from 'k6';

export function protocolIteration() {
  group('checkout', () => {
    http.get(`${BASE_URL}/cart`);
    http.post(`${BASE_URL}/api/checkout`, body);
    http.get(`${BASE_URL}/order-confirmation`);
  });
}

// threshold:
'group_duration{group:::checkout}': ['p(95)<2000'],
```

Use this for sub-iteration timing of a multi-step flow inside the
protocol body. Don't try it in browser code.

## Threshold layering summary

| Layer            | What                              | Where applied            |
|------------------|-----------------------------------|--------------------------|
| Global           | `http_req_failed`, aggregate p95  | All non-breakpoint types |
| Per-endpoint     | `http_req_duration{name:...}`     | All non-breakpoint types |
| Per-iteration    | `iteration_duration{scenario:browser}` | All non-breakpoint types |
| Web Vitals       | LCP / INP / CLS                   | All non-breakpoint types |
| Custom action    | `time_to_*` Trend                 | All non-breakpoint types |
| Iteration health | `iteration_completed` Rate        | All non-breakpoint types |
| Group duration   | `group_duration{group:::...}`     | Where sync protocol flow needs sub-timing |

For **breakpoint**, thresholds switch to abort-on-fail signals:

```js
thresholds: {
  http_req_failed: [{ threshold: 'rate<0.05', abortOnFail: true,
                      delayAbortEval: '30s' }],
  http_req_duration: [{ threshold: 'p(95)<2000', abortOnFail: true,
                        delayAbortEval: '30s' }],
  checks: ['rate>0.95'],
},
```

The point of breakpoint is to *find* where it breaks; abort-on-fail
stops the run at the cliff. See `test-types.md`.

## Tuning workflow

1. Start with the template defaults.
2. Run smoke and **read the actual results** for each threshold.
3. Adjust thresholds to be **2× the smoke p95** for non-critical
   endpoints, and to the user's stated SLO for critical ones.
4. Run average and stress; expect some thresholds to fail under
   stress — that's the whole point.
5. After all test types have run, the failing thresholds become
   the findings in the final report.

Don't loosen thresholds to make tests pass. Either:

- Confirm with the user that the SLO has shifted (and document it).
- Or report the failure and stop.
