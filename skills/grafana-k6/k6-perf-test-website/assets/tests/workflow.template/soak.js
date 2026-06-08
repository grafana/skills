// Hybrid k6 SOAK test for workflow <WORKFLOW_PLACEHOLDER>.
//
// SOAK: sustained moderate load over a long window. Goal is to find memory
// leaks, connection drift, scheduled-job interference, cache eviction patterns.
//
// Scenarios:
//   - protocol  : ramping-vus 0 → 10 → 0 over 70m (5m ramp / 60m hold / 5m drop)
//   - browser   : 1 constant VU × 70m
//
// COST WARNING (Grafana Cloud k6): a 70-minute browser VU costs ~12 VUh
// (browser VUs are billed 10×). This is one of the most budget-hostile test
// types in cloud. Confirm with the customer per runbook.md before pushing.
//
// CLIENT-SIDE NOTE: long browser soaks may show k6 RSS climbing on the LG.
// This is NOT necessarily a server-side leak -- k6 accumulates every metric
// sample for the run summary. Verify against backend memory metrics before
// reporting a leak.
//
// Iteration body is identical to smoke.js.
//
// Run:
//   ./tools/run-with-monitor.sh                tests/<WORKFLOW_PLACEHOLDER>/soak.js
//   k6 cloud run                               tests/<WORKFLOW_PLACEHOLDER>/soak.js   # only with customer confirmation

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { browser } from 'k6/browser';
import { Rate, Trend } from 'k6/metrics';
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
        { duration: '5m',  target: 10 },     // ramp up to soak level
        { duration: '60m', target: 10 },     // hold for an hour
        { duration: '5m',  target: 0  },     // ramp down
      ],
    },
    browser: {
      executor: 'constant-vus',
      exec: 'browserIteration',
      vus: 1,
      duration: '70m',
      options: { browser: { type: 'chromium' } },
    },
  },
  thresholds: { ...BACKEND_THRESHOLDS, ...BROWSER_THRESHOLDS },
};

// --- Protocol iteration ---------------------------------------------------------

export function protocolIteration() {
  group('<WORKFLOW_PLACEHOLDER>', function () {
    let res = http.get(`${BASE_URL}/`, {
      headers: {
        Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    });
    check(res, { 'homepage 200': (r) => r.status === 200 });

    // ... fill in from protocol.js with check() + tags. See smoke.js template.

    sleep(Math.random() * 3 + 1);

    // The user action (tagged)
  });
}

// --- Browser iteration ----------------------------------------------------------

export async function browserIteration() {
  const page = await browser.newPage();
  let success = true;

  try {
    await page.goto(BASE_URL, { waitUntil: 'load' });

    // ... fill in from browser.js with performance.mark/measure. See smoke.js.

  } catch (e) {
    success = false;
    console.error(`<WORKFLOW_PLACEHOLDER> browser iteration failed: ${(e && e.message) || e}`);
    throw e;
  } finally {
    iterationCompleted.add(success);
    await page.close();
  }
}
