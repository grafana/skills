---
name: testing
license: Apache-2.0
description: >
  Grafana Cloud testing capabilities — Synthetic Monitoring (probing URLs, DNS, TCP, ping from
  multiple regions), k6 Cloud (managed load testing with distributed execution), and Frontend
  Observability (Faro, real user monitoring). Use when setting up uptime checks, external probes,
  configuring k6 cloud runs, monitoring frontend performance, or testing APIs from multiple locations.
---

# Grafana Cloud Testing

> **Docs**: https://grafana.com/docs/grafana-cloud/testing/

## Synthetic Monitoring

Monitor uptime and performance from 20+ global locations without deploying your own agents.

### Check Types

| Check | Use Case |
|-------|----------|
| **HTTP** | Website and API availability, response validation |
| **DNS** | DNS resolution time and record validation |
| **TCP** | Port/service connectivity |
| **Ping** | ICMP availability |
| **Traceroute** | Network path diagnostics |
| **Multihttp** | Multi-step HTTP flows |
| **Scripted** (k6 browser) | Full browser-based user flow testing |

### HTTP Check Configuration (API)

```bash
curl -X POST https://synthetic-monitoring-api.grafana.net/sm/checks \
  -H "Authorization: Bearer <sm-access-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "job": "website",
    "target": "https://example.com",
    "frequency": 60000,
    "timeout": 15000,
    "enabled": true,
    "probes": [1, 5, 10],
    "settings": {
      "http": {
        "method": "GET",
        "ipVersion": "V4",
        "noFollowRedirects": false,
        "tlsConfig": {},
        "validStatusCodes": [200, 201],
        "validHTTPVersions": ["HTTP/1.1", "HTTP/2.0"],
        "failIfBodyMatchesRegexp": ["error", "exception"],
        "failIfBodyNotMatchesRegexp": ["OK"],
        "headers": [{"name": "User-Agent", "value": "Grafana-Synthetic-Monitoring"}]
      }
    }
  }'
```

### Synthetic Monitoring Metrics

```promql
# Probe success rate
sum(rate(probe_success[5m])) by (job, instance, probe)

# HTTP response time p95
histogram_quantile(0.95, sum(rate(probe_duration_seconds_bucket[5m])) by (le, job))

# DNS lookup time
avg(probe_dns_lookup_time_seconds) by (job, instance)

# TLS expiry days remaining
(probe_ssl_earliest_cert_expiry - time()) / 86400
```

### Alert on Synthetic Monitoring

```yaml
groups:
  - name: synthetic-monitoring
    rules:
      - alert: SyntheticCheckFailing
        expr: avg_over_time(probe_success[5m]) < 0.9
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.job }} failing from {{ $labels.probe }}"

      - alert: TLSCertExpiringSoon
        expr: (probe_ssl_earliest_cert_expiry - time()) / 86400 < 14
        labels:
          severity: warning
        annotations:
          summary: "TLS cert for {{ $labels.instance }} expires in {{ $value }} days"
```

## k6 Cloud (Grafana Cloud k6)

Run distributed load tests from multiple AWS regions without managing infrastructure.

### k6 Script for Cloud

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  cloud: {
    projectID: 3456789,
    name: 'API Load Test - Release v2.0',
    distribution: {
      loadZone1: { loadZone: 'amazon:us:ashburn', percent: 50 },
      loadZone2: { loadZone: 'amazon:eu:dublin', percent: 30 },
      loadZone3: { loadZone: 'amazon:ap:tokyo', percent: 20 },
    },
  },
  scenarios: {
    load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 100 },
        { duration: '10m', target: 100 },
        { duration: '2m', target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const res = http.get('https://api.example.com/users');
  check(res, {
    'status 200': (r) => r.status === 200,
    'fast': (r) => r.timings.duration < 500,
  });
  sleep(1);
}
```

```bash
# Authenticate
k6 cloud login --token <your-grafana-cloud-token>

# Run in cloud
k6 cloud script.js

# Run locally but stream to cloud
k6 run --out cloud script.js
```

### k6 Cloud Test Runs API

```bash
# List test runs
curl https://api.k6.io/v3/projects/{projectId}/test-runs \
  -H "Authorization: Token <token>"

# Get test run results
curl https://api.k6.io/v3/runs/{runId} \
  -H "Authorization: Token <token>"

# Stop a running test
curl -X POST https://api.k6.io/v3/runs/{runId}/stop \
  -H "Authorization: Token <token>"
```

### CI/CD Integration

```yaml
# GitHub Actions
- name: Run k6 Load Test
  uses: grafana/k6-action@v0.3.1
  with:
    filename: tests/load.js
    cloud: true
    token: ${{ secrets.K6_CLOUD_TOKEN }}
    flags: --out cloud
```

## Frontend Observability (Faro / RUM)

```javascript
// Initialize Faro in your web app
import { initializeFaro, getWebInstrumentations } from '@grafana/faro-web-sdk';
import { TracingInstrumentation } from '@grafana/faro-web-tracing';

const faro = initializeFaro({
  url: 'https://faro-collector-prod-xx.grafana.net/collect',
  apiKey: 'your-faro-api-key',
  app: {
    name: 'my-frontend',
    version: '1.0.0',
    environment: 'production',
  },
  instrumentations: [
    ...getWebInstrumentations({
      captureConsole: true,
      captureConsoleDisabledLevels: [],
    }),
    new TracingInstrumentation(),
  ],
});

// Custom events
faro.api.pushEvent('checkout_completed', { cart_value: '99.99' });

// Custom measurements
faro.api.pushMeasurement({ type: 'api_latency', values: { ms: 234 } });

// Error capturing
faro.api.pushError(new Error('Payment failed'));
```

```bash
# Install
npm install @grafana/faro-web-sdk @grafana/faro-web-tracing
```
