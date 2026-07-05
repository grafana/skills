// k6 BREAKPOINT test for workflow <WORKFLOW_PLACEHOLDER>.
//
// BREAKPOINT: ramping arrival rate, find the ceiling. PROTOCOL-ONLY -- a single
// browser VU mid-test adds noise to the signal we're hunting. Document the
// abort point (final iteration rate or arrival rate) as the breakpoint.
//
// `ramping-arrival-rate` (not VUs) because the cliff is in requests-per-second,
// not concurrent users. VU-based ramps are bounded by iteration duration; if
// iterations slow down, VUs back off and you never reach the cliff. Arrival
// rate injects requests on a fixed schedule.
//
// `abortOnFail` thresholds stop the run when SLOs break. `delayAbortEval` 30s
// avoids tripping on instantaneous fluctuations.
//
// COST WARNING (Grafana Cloud k6): breakpoint runs can use 30-100+ VUh.
// Confirm with the customer per runbook.md before pushing.
//
// Iteration body mirrors smoke.js's protocolIteration (no browser body here)
// with ONE deliberate difference: NO think-time sleep(). Breakpoint hunts raw
// requests-per-second, and with `ramping-arrival-rate` every started iteration
// holds a VU until it finishes. A 1-4s think-time sleep makes each iteration
// last ~2.5s, so each VU can only serve ~0.4 iters/s. k6 then hits the maxVUs
// cap, logs "Insufficient VUs", and drops iterations -- the arrival rate
// plateaus from VU exhaustion long before the backend's real ceiling, which is
// easy to misread as "the server broke". Keep think-time out of breakpoint;
// it belongs in average/stress/soak where it models real user pacing.
//
// Run:
//   ./tools/run-with-monitor.sh                tests/<WORKFLOW_PLACEHOLDER>/breakpoint.js
//   k6 cloud run                               tests/<WORKFLOW_PLACEHOLDER>/breakpoint.js   # confirm budget

import http from 'k6/http';
import { check, group } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'https://target-host.example';
const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';

export const options = {
  userAgent: USER_AGENT,
  scenarios: {
    protocol: {
      executor: 'ramping-arrival-rate',
      exec: 'protocolIteration',
      startRate: 5,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      // maxVUs must exceed target_rate × expected_iteration_seconds, or k6 runs
      // out of VUs and the arrival rate plateaus before the real ceiling. With
      // no think-time and a ~0.2s iteration, 500/s needs ~100 VUs, so 500 is
      // ample headroom. If your iteration is slower, raise this accordingly.
      maxVUs: 500,
      stages: [
        { duration: '20m', target: 500 },    // ramp arrival rate 5/s → 500/s
      ],
    },
    // NO browser scenario -- breakpoint hunts protocol throughput. Adding a
    // browser VU adds noise without contributing signal.
  },
  thresholds: {
    // abortOnFail: stop the run when SLOs break -- that's the breakpoint.
    http_req_failed: [
      { threshold: 'rate<0.05', abortOnFail: true, delayAbortEval: '30s' },
    ],
    http_req_duration: [
      { threshold: 'p(95)<2000', abortOnFail: true, delayAbortEval: '30s' },
    ],
    checks: ['rate>0.95'],
  },
};

// --- Protocol iteration ---------------------------------------------------------
// Mirrors smoke.js's protocolIteration MINUS the think-time sleep() (see the
// header note for why). See smoke.js for the full template and
// hybrid-load-design.md for why duplication is preferred over a shared helper.

export function protocolIteration() {
  group('<WORKFLOW_PLACEHOLDER>', function () {
    let res = http.get(`${BASE_URL}/`, {
      headers: {
        Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    });
    check(res, { 'homepage 200': (r) => r.status === 200 });

    // ... fill in from protocol.js with check() + tags. See smoke.js template.
    // Do NOT add a think-time sleep() here -- it caps achievable arrival rate
    // via VU exhaustion. The user action (tagged) goes here, back-to-back.
  });
}
