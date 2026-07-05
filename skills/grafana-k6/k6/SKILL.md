---
name: k6
license: Apache-2.0
description: >
  k6 performance and load testing. Covers writing test scripts in JavaScript/TypeScript, all test types
  (load/stress/spike/soak/smoke/breakpoint), thresholds, checks, scenarios, executors, extensions,
  result analysis, k6 Cloud execution, and CI/CD integration. Use when writing k6 tests, debugging
  test failures, setting up load testing pipelines, choosing executors/scenarios, or interpreting k6 results.
---

# k6 Performance Testing

> **Docs**: https://grafana.com/docs/k6/latest/

## Quick Start

```bash
# Install
brew install k6                          # macOS
sudo apt install k6                      # Ubuntu/Debian
choco install k6                         # Windows

# Run a test
k6 run script.js
k6 run --vus 10 --duration 30s script.js
k6 run --out json=results.json script.js
```

## Basic Script Structure

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 10,
  duration: '30s',
  thresholds: {
    http_req_duration: ['p(95)<500'],   // 95% of requests under 500ms
    http_req_failed: ['rate<0.01'],     // error rate under 1%
  },
};

export default function () {
  const res = http.get('https://test.k6.io');
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time OK': (r) => r.timings.duration < 500,
  });
  sleep(1);
}
```

## Test Lifecycle

```javascript
export function setup() {
  // Runs once before all VUs — return data shared with VUs
  const token = getAuthToken();
  return { token };
}

export default function (data) {
  // Runs for each VU iteration — receives setup() return value
  http.get('https://api.example.com', {
    headers: { Authorization: `Bearer ${data.token}` },
  });
}

export function teardown(data) {
  // Runs once after all VUs finish
  console.log('Test complete');
}
```

## HTTP Requests

```javascript
import http from 'k6/http';

// GET
const res = http.get('https://api.example.com/users');

// POST with JSON body
const payload = JSON.stringify({ name: 'test', value: 42 });
const params = { headers: { 'Content-Type': 'application/json' } };
const res = http.post('https://api.example.com/users', payload, params);

// PUT / PATCH / DELETE
http.put(url, body, params);
http.patch(url, body, params);
http.del(url, null, params);

// Batch requests (parallel)
const responses = http.batch([
  ['GET', 'https://api.example.com/users'],
  ['GET', 'https://api.example.com/posts'],
]);

// With auth
const res = http.get(url, {
  headers: { Authorization: 'Bearer token123' },
});

// Form data
const res = http.post(url, { username: 'user', password: 'pass' });

// File upload
const binFile = open('./image.png', 'b');
const res = http.post(url, {
  file: http.file(binFile, 'image.png', 'image/png'),
  field: 'value',
});
```

## Checks and Thresholds

```javascript
import { check } from 'k6';

// Checks (soft assertions — don't stop test on failure)
const res = http.get(url);
check(res, {
  'status 200': (r) => r.status === 200,
  'body contains ID': (r) => r.body.includes('"id"'),
  'duration < 500ms': (r) => r.timings.duration < 500,
});

// Thresholds (hard pass/fail criteria)
export const options = {
  thresholds: {
    // HTTP metrics
    http_req_duration: ['p(90)<400', 'p(95)<800', 'avg<200'],
    http_req_failed: ['rate<0.05'],

    // Custom metric thresholds
    my_errors: ['count<10'],

    // Tag-based thresholds (specific endpoints)
    'http_req_duration{name:homepage}': ['p(95)<500'],

    // Abort test if threshold breached
    http_req_duration: [{ threshold: 'p(99)<3000', abortOnFail: true }],
  },
};
```

## Custom Metrics

```javascript
import { Counter, Gauge, Rate, Trend } from 'k6/metrics';

const myErrors = new Counter('my_errors');
const activeUsers = new Gauge('active_users');
const successRate = new Rate('success_rate');
const reqDuration = new Trend('req_duration', true); // true = display in ms

export default function () {
  const res = http.get(url);
  if (res.status !== 200) myErrors.add(1);
  successRate.add(res.status === 200);
  reqDuration.add(res.timings.duration);
}
```

## Scenarios and Executors

See `references/scenarios-executors.md` for full reference.

```javascript
export const options = {
  scenarios: {
    // Constant VUs
    steady_load: {
      executor: 'constant-vus',
      vus: 50,
      duration: '5m',
    },
    // Ramping VUs (most common)
    ramp_up: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 100 },
        { duration: '5m', target: 100 },
        { duration: '2m', target: 0 },
      ],
    },
    // Constant arrival rate (requests per second)
    constant_rps: {
      executor: 'constant-arrival-rate',
      rate: 100,             // 100 iterations/sec
      timeUnit: '1s',
      duration: '5m',
      preAllocatedVUs: 50,
      maxVUs: 200,
    },
    // Per-VU iterations
    per_vu: {
      executor: 'per-vu-iterations',
      vus: 10,
      iterations: 100,
    },
  },
};
```

## Test Types

See `references/test-types.md` for full examples.

| Type | Purpose | Load Pattern |
|------|---------|-------------|
| **Smoke** | Verify script works, minimal load | 1-2 VUs, short duration |
| **Load** | Normal expected load | Ramp up → steady → ramp down |
| **Stress** | Beyond normal capacity | Increasing stages until breaking |
| **Spike** | Sudden traffic surge | Instant spike then drop |
| **Soak** | Extended duration for memory leaks | Moderate load, hours-long |
| **Breakpoint** | Find system limits | Continuously increasing load |

## Environment Variables and CLI Flags

```bash
# Pass variables to script
k6 run -e MY_VAR=value script.js     # access as __ENV.MY_VAR
k6 run --env API_URL=https://api.example.com script.js

# Override options
k6 run --vus 50 --duration 60s script.js
k6 run --iterations 1000 script.js
k6 run --stage 30s:10,1m:50,30s:0 script.js   # ramping stages

# Output formats
k6 run --out json=result.json script.js
k6 run --out csv=result.csv script.js
k6 run --out influxdb=http://localhost:8086/k6 script.js
k6 run --out statsd script.js
```

## Groups and Tags

```javascript
import { group } from 'k6';

export default function () {
  group('homepage', () => {
    const res = http.get('/');
    check(res, { 'status 200': (r) => r.status === 200 });
  });

  group('login flow', () => {
    group('load login page', () => {
      http.get('/login');
    });
    group('submit credentials', () => {
      http.post('/login', { user: 'test', pass: 'test' });
    });
  });
}

// Custom tags on requests
http.get(url, { tags: { name: 'homepage', version: 'v2' } });
```

## WebSocket

```javascript
import ws from 'k6/ws';
import { check } from 'k6';

export default function () {
  const url = 'ws://echo.websocket.org';
  const res = ws.connect(url, {}, function (socket) {
    socket.on('open', () => {
      socket.send('Hello!');
      socket.setInterval(() => socket.ping(), 10000);
    });
    socket.on('message', (data) => {
      check(data, { 'message received': (d) => d.length > 0 });
    });
    socket.on('error', (e) => console.error(e.error()));
    socket.setTimeout(() => socket.close(), 30000);
  });
  check(res, { 'status 101': (r) => r.status === 101 });
}
```

## Browser Testing

```javascript
import { browser } from 'k6/browser';
import { check } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

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
    await page.goto('https://test.k6.io/my_messages.php');
    await page.locator('input[name="login"]').type('admin');
    await page.locator('input[name="password"]').type('123');
    await Promise.all([
      page.waitForNavigation(),
      page.locator('input[type="submit"]').click(),
    ]);
    check(page, { 'header': p => p.locator('h2').textContent() == 'Welcome, admin!' });
  } finally {
    await page.close();
  }
}
```

## Modules and Imports

```javascript
// Built-in modules
import http from 'k6/http';
import { check, group, sleep, fail } from 'k6';
import { Counter, Gauge, Rate, Trend } from 'k6/metrics';
import { SharedArray } from 'k6/data';
import { scenario, vu } from 'k6/execution';
import ws from 'k6/ws';
import grpc from 'k6/net/grpc';
import { browser } from 'k6/browser';
import crypto from 'k6/crypto';
import encoding from 'k6/encoding';
import { htmlReport } from 'https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js';

// jslib utilities
import { uuidv4 } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';
import { randomItem, randomIntBetween } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';
```

## SharedArray (efficient data loading)

```javascript
import { SharedArray } from 'k6/data';
import papaparse from 'https://jslib.k6.io/papaparse/5.1.1/index.js';

// Load CSV once, shared across all VUs
const users = new SharedArray('users', function () {
  return papaparse.parse(open('./users.csv'), { header: true }).data;
});

// Load JSON
const data = new SharedArray('data', function () {
  return JSON.parse(open('./data.json'));
});

export default function () {
  const user = users[Math.floor(Math.random() * users.length)];
  http.post('/login', { username: user.username, password: user.password });
}
```

## k6 Cloud (Grafana Cloud k6)

```javascript
export const options = {
  cloud: {
    projectID: 123456,
    name: 'My Load Test',
    note: 'Release candidate',
    distribution: {
      distributionLabel1: { loadZone: 'amazon:us:ashburn', percent: 50 },
      distributionLabel2: { loadZone: 'amazon:eu:dublin', percent: 50 },
    },
  },
};
```

```bash
# Authenticate
k6 cloud login --token <your-token>

# Run in cloud
k6 cloud script.js

# Run locally but stream results to cloud
k6 run --out cloud script.js
```

## CLI Flags Summary

| Flag | Description |
|------|-------------|
| `--vus N` | Number of virtual users |
| `--duration Xs/Xm/Xh` | Test duration |
| `--iterations N` | Total iterations |
| `--stage Xm:N` | Add ramp stage |
| `--env KEY=value` | Environment variable |
| `--out FORMAT` | Output destination |
| `--quiet` | Suppress progress output |
| `--no-summary` | Skip end-of-test summary |
| `--summary-export FILE` | Export summary as JSON |
| `--http-debug` | Print HTTP request/response details |
| `--insecure-skip-tls-verify` | Skip TLS verification |
| `--tag KEY=VALUE` | Add test-wide tag |

## Key Built-in Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `http_req_duration` | Trend | Total request time |
| `http_req_failed` | Rate | Failed request rate |
| `http_req_waiting` | Trend | Time to first byte (TTFB) |
| `http_req_connecting` | Trend | TCP connection time |
| `http_req_tls_handshaking` | Trend | TLS handshake time |
| `http_reqs` | Counter | Total HTTP requests |
| `vus` | Gauge | Current active VUs |
| `vus_max` | Gauge | Max VUs allocated |
| `iterations` | Counter | Total VU iterations |
| `iteration_duration` | Trend | Time to complete one iteration |
| `data_sent` | Counter | Data sent |
| `data_received` | Counter | Data received |
| `checks` | Rate | Check success rate |

## References

- [JavaScript API](references/javascript-api.md)
- [Test Types](references/test-types.md)
- [Scenarios & Executors](references/scenarios-executors.md)
- [Examples](references/examples.md)
