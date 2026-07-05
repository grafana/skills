# k6 Cloud + Faro RUM — full snippets

## k6 cloud script

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  cloud: {
    projectID: 3456789,
    name: 'API Load Test - Release v2.0',
    distribution: {
      loadZone1: { loadZone: 'amazon:us:ashburn', percent: 50 },
      loadZone2: { loadZone: 'amazon:eu:dublin',  percent: 30 },
      loadZone3: { loadZone: 'amazon:ap:tokyo',   percent: 20 },
    },
  },
  scenarios: {
    load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m',  target: 100 },
        { duration: '10m', target: 100 },
        { duration: '2m',  target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed:   ['rate<0.01'],
  },
};

export default function () {
  const res = http.get('https://api.example.com/users');
  check(res, {
    'status 200': (r) => r.status === 200,
    'fast':       (r) => r.timings.duration < 500,
  });
  sleep(1);
}
```

## k6 Cloud commands

```bash
# Authenticate
k6 cloud login --token <your-grafana-cloud-token>

# Run in cloud
k6 cloud script.js

# Run locally, stream results to cloud
k6 run --out cloud script.js
```

## k6 Cloud API

```bash
# List test runs
curl https://api.k6.io/v3/projects/{projectId}/test-runs -H "Authorization: Token <token>"

# Get test run results
curl https://api.k6.io/v3/runs/{runId} -H "Authorization: Token <token>"

# Stop a running test
curl -X POST https://api.k6.io/v3/runs/{runId}/stop -H "Authorization: Token <token>"
```

## GitHub Actions

```yaml
- name: Run k6 Load Test
  uses: grafana/k6-action@v0.3.1
  with:
    filename: tests/load.js
    cloud: true
    token: ${{ secrets.K6_CLOUD_TOKEN }}
    flags: --out cloud
```

## Faro / Frontend Observability

```bash
npm install @grafana/faro-web-sdk @grafana/faro-web-tracing
```

```javascript
import { initializeFaro, getWebInstrumentations } from '@grafana/faro-web-sdk';
import { TracingInstrumentation } from '@grafana/faro-web-tracing';

const faro = initializeFaro({
  url: 'https://faro-collector-prod-xx.grafana.net/collect',
  apiKey: 'your-faro-api-key',
  app: { name: 'my-frontend', version: '1.0.0', environment: 'production' },
  instrumentations: [
    ...getWebInstrumentations({ captureConsole: true, captureConsoleDisabledLevels: [] }),
    new TracingInstrumentation(),
  ],
});

// Custom events / measurements / errors
faro.api.pushEvent('checkout_completed', { cart_value: '99.99' });
faro.api.pushMeasurement({ type: 'api_latency', values: { ms: 234 } });
faro.api.pushError(new Error('Payment failed'));
```
