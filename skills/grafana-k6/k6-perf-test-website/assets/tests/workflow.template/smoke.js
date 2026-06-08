// Hybrid k6 SMOKE test for workflow <WORKFLOW_PLACEHOLDER>.
//
// SMOKE: low VUs, short duration, sanity check. Always run before any other
// test type. If smoke fails, fix the script before scaling.
//
// Scenarios:
//   - protocol  : 3 constant VUs × 1m, drives the bulk of the load
//   - browser   : 1 constant VU × 1m, measures Web Vitals under load
//
// Run:
//   k6 run                                     tests/<WORKFLOW_PLACEHOLDER>/smoke.js
//   ./tools/run-with-monitor.sh                tests/<WORKFLOW_PLACEHOLDER>/smoke.js
//   BASE_URL=http://localhost:3333 k6 run      tests/<WORKFLOW_PLACEHOLDER>/smoke.js
//   k6 cloud run                               tests/<WORKFLOW_PLACEHOLDER>/smoke.js

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { browser } from 'k6/browser';
import { Rate, Trend } from 'k6/metrics';
import { check as asyncCheck } from 'https://jslib.k6.io/k6-utils/1.5.0/index.js';

// --- Custom metrics -------------------------------------------------------------

// Time from "user clicks the action button" to "result is visible". Web Vitals
// measure initial render; this Trend captures the slow action specifically.
// Implemented via performance.mark/measure (group() does NOT work in async code).
const timeToResult = new Trend('time_to_result', true);

// Browser iterations can throw on locator timeouts. A thrown iteration is
// "interrupted" in k6's summary, not "failed". This Rate makes failures visible.
const iterationCompleted = new Rate('iteration_completed');

// --- Configuration --------------------------------------------------------------

const BASE_URL = __ENV.BASE_URL || 'https://target-host.example';
const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';

// --- Thresholds -----------------------------------------------------------------

const BACKEND_THRESHOLDS = {
  // < 1% failures. NOTE: k6 counts any 4xx/5xx as a "failed" request by default.
  // If your workflow intentionally produces a non-2xx (e.g. anonymous user
  // returns 401, "not found" returns 404), this threshold will blow because
  // those expected failures count against it. See references/gotchas.md
  // ("Workflows with expected 4xx/5xx responses") for two correct fixes:
  // (A) http.setResponseCallback(http.expectedStatuses({min:200,max:299}, 401))
  //     at the top of the module, or (B) tag the expected-failure request and
  //     threshold its tag separately. Do NOT just relax this number — that
  //     hides real failures elsewhere.
  http_req_failed: ['rate<0.01'],
  http_req_duration: ['p(95)<500'],          // global p95 < 500ms
  checks: ['rate>0.99'],
  // EXAMPLE per-endpoint thresholds (add a tag to each http.* call in the
  // protocolIteration body via `tags: { name: 'GetThings' }`, then threshold):
  // 'http_req_duration{name:GetConfig}': ['p(95)<300'],
  // 'http_req_duration{name:GetAction}': ['p(95)<1000', 'p(99)<1500'],
};

const BROWSER_THRESHOLDS = {
  // Web Vitals (Google "good" thresholds; loosen with documentation only)
  browser_web_vital_lcp: ['p(95)<2500'],
  browser_web_vital_inp: ['p(95)<200'],
  browser_web_vital_cls: ['p(95)<0.1'],
  // User-perceived workflow time
  'iteration_duration{scenario:browser}': ['p(95)<10000'],   // 10s end-to-end
  // Custom action time (for the slow user action specifically).
  // WARNING: this threshold PASSES VACUOUSLY until you wire up timeToResult.add()
  // in browserIteration (it's commented out in the example body below). k6 treats
  // a metric with zero samples as non-violating, so an unfilled time_to_result
  // shows green while measuring nothing -- false comfort. Either wire up the
  // performance.mark/measure block or delete this threshold; don't ship it empty.
  time_to_result: ['p(95)<3000'],                            // click → result: 3s
  // Browser iteration health
  'iteration_completed{scenario:browser}': ['rate>0.99'],    // <1% throws
};

// --- Options --------------------------------------------------------------------

export const options = {
  userAgent: USER_AGENT,
  scenarios: {
    protocol: {
      executor: 'constant-vus',
      exec: 'protocolIteration',
      vus: 3,
      duration: '1m',
    },
    browser: {
      executor: 'constant-vus',
      exec: 'browserIteration',
      vus: 1,
      duration: '1m',
      options: { browser: { type: 'chromium' } },
    },
  },
  thresholds: { ...BACKEND_THRESHOLDS, ...BROWSER_THRESHOLDS },
};

// --- Protocol iteration ---------------------------------------------------------

export function protocolIteration() {
  group('<WORKFLOW_PLACEHOLDER>', function () {
    // ============================================================================
    // PROTOCOL ITERATION BODY -- structurally identical to protocol.js but with
    // check() (not expect()), per-endpoint tags, and randomised sleep between
    // user actions.
    //
    // Pattern:
    //   1. Homepage shell
    //   2. Static assets
    //   3. onMount API fan-out (tag each endpoint)
    //   4. sleep(random think time) -- simulate user reading the page
    //   5. The user action (tag it)
    //   6. Trailing fetches
    //
    // No trailing sleep -- closed-model executors pace via VU count.
    // ============================================================================

    // EXAMPLE -- replace with the actual workflow body:

    let res = http.get(`${BASE_URL}/`, {
      headers: {
        Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    });
    check(res, { 'homepage 200': (r) => r.status === 200 });

    // res = http.get(`${BASE_URL}/api/config`, {
    //   headers: { Referer: `${BASE_URL}/` },
    //   tags: { name: 'GetConfig' },
    // });
    // check(res, { 'config 200': (r) => r.status === 200 });

    // User reads the page, decides to act.
    sleep(Math.random() * 3 + 1);

    // The action -- tag it for per-endpoint thresholding.
    // res = http.post(`${BASE_URL}/api/action`, JSON.stringify({ /* payload */ }), {
    //   headers: { 'Content-Type': 'application/json', Referer: `${BASE_URL}/` },
    //   tags: { name: 'GetAction' },
    // });
    // check(res, {
    //   'action 200': (r) => r.status === 200,
    //   'action has result': (r) => r.json('result') != null,
    // });
  });
}

// --- Browser iteration ----------------------------------------------------------

export async function browserIteration() {
  const page = await browser.newPage();
  let success = true;

  try {
    // Open homepage, wait for hydration sentinel.
    await page.goto(BASE_URL, { waitUntil: 'load' });

    // EXAMPLE -- replace with the actual workflow:

    // const primaryAction = page.locator('button[name="primary-action"]');
    // await primaryAction.waitFor({ state: 'visible' });

    // // Think time before clicking.
    // await page.waitForTimeout(1000 + Math.random() * 3000);

    // // Mark the start of the slow action in the Performance Timeline.
    // await page.evaluate(() => performance.mark('action-start'));

    // await Promise.all([
    //   page.waitForResponse(
    //     (r) => r.url().includes('/api/action') && r.request().method() === 'POST',
    //   ),
    //   primaryAction.click(),
    // ]);

    // const result = page.locator('#result');
    // await result.waitFor({ state: 'visible' });

    // // Record the time-to-result.
    // const ms = await page.evaluate(() => {
    //   performance.mark('action-end');
    //   return performance.measure('time-to-result', 'action-start', 'action-end').duration;
    // });
    // timeToResult.add(ms);

    // // Async check (records in `checks` rate, doesn't abort).
    // await asyncCheck(result, {
    //   'result visible': async (lo) => (await lo.isVisible()) === true,
    // });

  } catch (e) {
    success = false;
    console.error(`<WORKFLOW_PLACEHOLDER> browser iteration failed: ${(e && e.message) || e}`);
    throw e;          // re-throw so k6 also marks the iteration interrupted
  } finally {
    iterationCompleted.add(success);
    await page.close();
  }
}
