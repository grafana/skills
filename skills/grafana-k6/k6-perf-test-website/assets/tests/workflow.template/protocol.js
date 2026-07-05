// k6 protocol-level functional test for workflow <WORKFLOW_PLACEHOLDER>.
//
// Hand-cleaned from from-har.js per the k6-perf-test-website skill's
// functional-tests.md procedure.
//
// Run:
//   k6 run tests/<WORKFLOW_PLACEHOLDER>/protocol.js
//   BASE_URL=http://localhost:3333 k6 run tests/<WORKFLOW_PLACEHOLDER>/protocol.js

import http from 'k6/http';
import { group } from 'k6';
import { expect } from 'https://jslib.k6.io/k6-testing/0.5.0/index.js';

// --- Configuration --------------------------------------------------------------

const BASE_URL = __ENV.BASE_URL || 'https://target-host.example';

// Real Chrome UA -- headless UAs trigger bot-blocking on production sites.
const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';

// Auth -- if your workflow needs a token, set TEST_TOKEN env or hard-code a
// well-known test value here. Do not commit production credentials.
// const AUTH_TOKEN = __ENV.TEST_TOKEN || 'replace-with-test-token';

export const options = {
  vus: 1,
  iterations: 1,
  userAgent: USER_AGENT,
};

// --- Iteration body -------------------------------------------------------------

export default function () {
  group('<WORKFLOW_PLACEHOLDER>', function () {
    // ============================================================================
    // PROTOCOL ITERATION -- replace this block with the cleaned-up sequence from
    // from-har.js. Pattern:
    //
    //   1. Homepage shell (HTML) -- expect 200.
    //   2. Static assets (CSS/JS) -- expect 200 on each. A 404 on a hash-named
    //      bundle is the expected failure mode when the app is rebuilt; the
    //      test must fail loudly so the recorder is re-run.
    //   3. onMount API fan-out -- expect 200 + body-shape assertions on the
    //      load-bearing responses.
    //   4. The user action(s) -- expect 200 + body-shape assertions on the
    //      response that carries the workflow's payload.
    //   5. Trailing fetches (CSS background-image, etc.).
    //
    // Every http.* call gets at least an expect() on res.status.
    // The response that carries the workflow's payload gets additional
    // body-shape assertions.
    // ============================================================================

    // EXAMPLE -- replace with the actual workflow:

    // 1. Homepage shell
    let res = http.get(`${BASE_URL}/`, {
      headers: {
        Accept:
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Upgrade-Insecure-Requests': '1',
      },
    });
    expect(res.status).toBe(200);

    // 2. Static assets -- list every asset captured in the HAR, with status
    //    assertion on each so a hash-rename failure is obvious.
    // const assets = [
    //   ['css', '/_app/immutable/assets/0.<hash>.css'],
    //   ['js',  '/_app/immutable/entry/start.<hash>.js'],
    //   // ...
    // ];
    // for (const [kind, path] of assets) {
    //   const r = http.get(`${BASE_URL}${path}`, {
    //     headers: {
    //       Accept: kind === 'css' ? 'text/css,*/*;q=0.1' : '*/*',
    //       Referer: `${BASE_URL}/`,
    //     },
    //   });
    //   expect(r.status, `asset ${path}`).toBe(200);
    // }

    // 3. onMount API fan-out
    // res = http.get(`${BASE_URL}/api/config`, { headers: { Referer: `${BASE_URL}/` } });
    // expect(res.status).toBe(200);

    // 4. The user action
    // const payload = JSON.stringify({ /* request body */ });
    // res = http.post(`${BASE_URL}/api/action`, payload, {
    //   headers: {
    //     Accept: '*/*',
    //     'Content-Type': 'application/json',
    //     Origin: BASE_URL,
    //     Referer: `${BASE_URL}/`,
    //   },
    // });
    // expect(res.status).toBe(200);
    // const result = res.json('result');
    // expect(result).not.toBeNull();

    // 5. Trailing fetches (if any in the HAR)
  });
}
