// Hybrid k6 AVERAGE-LOAD test for workflow <WORKFLOW_PLACEHOLDER>.
//
// AVERAGE: expected production load. Tune target VUs to match the customer's
// typical concurrent user count from runbook.md.
//
// Scenarios:
//   - protocol  : ramping-vus 0 → 20 → 0 over 14m
//   - browser   : 1 constant VU × 14m (Web Vitals canary)
//
// Iteration body is identical to smoke.js -- duplication is intentional per the
// k6-perf-test-website skill's hybrid-load-design.md. Update both files in lock-step
// when the workflow body changes.
//
// Run:
//   ./tools/run-with-monitor.sh                tests/<WORKFLOW_PLACEHOLDER>/average.js
//   k6 cloud run                               tests/<WORKFLOW_PLACEHOLDER>/average.js

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { browser } from 'k6/browser';
import { Rate, Trend } from 'k6/metrics';
// asyncCheck (not bare check from k6) is required for async browser locators — see references/gotchas.md
import { check as asyncCheck } from 'https://jslib.k6.io/k6-utils/1.5.0/index.js';

const timeToResult = new Trend('time_to_result', true);
const iterationCompleted = new Rate('iteration_completed');

const BASE_URL = __ENV.BASE_URL || 'https://target-host.example';
const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';

const BACKEND_THRESHOLDS = {
  http_req_failed: ['rate<0.01'],
  http_req_duration: ['p(95)<500'],
  checks: ['rate>0.99'],
  // 'http_req_duration{name:GetConfig}': ['p(95)<300'],
  // 'http_req_duration{name:GetAction}': ['p(95)<1000', 'p(99)<1500'],
};

const BROWSER_THRESHOLDS = {
  browser_web_vital_lcp: ['p(95)<2500'],
  browser_web_vital_inp: ['p(95)<200'],
  browser_web_vital_cls: ['p(95)<0.1'],
  'iteration_duration{scenario:browser}': ['p(95)<10000'],
  time_to_result: ['p(95)<3000'],
  'iteration_completed{scenario:browser}': ['rate>0.99'],
};

export const options = {
  userAgent: USER_AGENT,
  scenarios: {
    protocol: {
      executor: 'ramping-vus',
      exec: 'protocolIteration',
      startVUs: 0,
      stages: [
        { duration: '2m',  target: 20 },     // ramp up
        { duration: '10m', target: 20 },     // hold at expected load
        { duration: '2m',  target: 0  },     // ramp down
      ],
    },
    browser: {
      executor: 'constant-vus',
      exec: 'browserIteration',
      vus: 1,
      duration: '14m',
      options: { browser: { type: 'chromium' } },
    },
  },
  thresholds: { ...BACKEND_THRESHOLDS, ...BROWSER_THRESHOLDS },
};

// --- Protocol iteration ---------------------------------------------------------
// Body identical to smoke.js -- duplicate so each file reads cleanly on its own
// during incident review. See hybrid-load-design.md for the rationale.

export function protocolIteration() {
  group('<WORKFLOW_PLACEHOLDER>', function () {
    let res = http.get(`${BASE_URL}/`, {
      headers: {
        Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    });
    check(res, { 'homepage 200': (r) => r.status === 200 });

    // ... fill in the rest of the protocol body from protocol.js ...
    // Use check() instead of expect(), and add tags: { name: 'EndpointName' } per
    // request. See smoke.js for the full template.

    sleep(Math.random() * 3 + 1);

    // The user action (tagged)
  });
}

// --- Browser iteration ----------------------------------------------------------
// Body identical to smoke.js.

export async function browserIteration() {
  const page = await browser.newPage();
  let success = true;

  try {
    await page.goto(BASE_URL, { waitUntil: 'load' });

    // ... fill in the browser iteration from browser.js, with performance.mark /
    // measure to record the time_to_result Trend. See smoke.js for the full
    // template.

  } catch (e) {
    success = false;
    console.error(`<WORKFLOW_PLACEHOLDER> browser iteration failed: ${(e && e.message) || e}`);
    throw e;
  } finally {
    iterationCompleted.add(success);
    await page.close();
  }
}
