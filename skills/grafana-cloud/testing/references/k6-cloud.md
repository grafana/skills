# k6 Cloud Reference

## Authentication

```bash
# Via token
k6 cloud login --token <your-grafana-cloud-token>

# Via environment variable
export K6_CLOUD_TOKEN=<your-token>

# Verify
k6 cloud login --show
```

## Run Commands

```bash
# Run in cloud (full cloud execution)
k6 cloud script.js

# Run locally, stream results to cloud
k6 run --out cloud script.js

# Run with environment variables
k6 cloud -e API_URL=https://api.example.com script.js

# Run with specific project
k6 cloud --project-id 123456 script.js

# Local execution (run on cloud infra but with local VUs)
k6 cloud run --local-execution script.js
```

## options.cloud Reference

```javascript
export const options = {
  cloud: {
    // Required
    projectID: 3456789,

    // Optional
    name: 'API Load Test - Release v2.0',
    note: 'Testing new checkout flow',

    // Load zone distribution
    distribution: {
      loadZone1: { loadZone: 'amazon:us:ashburn',    percent: 40 },
      loadZone2: { loadZone: 'amazon:us:portland',   percent: 20 },
      loadZone3: { loadZone: 'amazon:eu:dublin',     percent: 20 },
      loadZone4: { loadZone: 'amazon:ap:singapore',  percent: 20 },
    },

    // Static IPs (Enterprise)
    staticIPs: false,
  },
};
```

## Load Zones

### Americas
| Zone ID | Location |
|---------|----------|
| `amazon:us:ashburn` | Ashburn, Virginia, USA |
| `amazon:us:columbus` | Columbus, Ohio, USA |
| `amazon:us:portland` | Portland, Oregon, USA |
| `amazon:us:montreal` | Montréal, Canada |
| `amazon:sa:sao paulo` | São Paulo, Brazil |

### Europe
| Zone ID | Location |
|---------|----------|
| `amazon:eu:dublin` | Dublin, Ireland |
| `amazon:eu:frankfurt` | Frankfurt, Germany |
| `amazon:eu:london` | London, UK |
| `amazon:eu:paris` | Paris, France |
| `amazon:eu:stockholm` | Stockholm, Sweden |
| `amazon:eu:milan` | Milan, Italy |

### Asia Pacific
| Zone ID | Location |
|---------|----------|
| `amazon:ap:singapore` | Singapore |
| `amazon:ap:sydney` | Sydney, Australia |
| `amazon:ap:tokyo` | Tokyo, Japan |
| `amazon:ap:mumbai` | Mumbai, India |
| `amazon:ap:seoul` | Seoul, South Korea |
| `amazon:ap:hong kong` | Hong Kong |
| `amazon:ap:osaka` | Osaka, Japan |
| `amazon:ap:jakarta` | Jakarta, Indonesia |
| `amazon:ap:cape town` | Cape Town, South Africa |
| `amazon:me:bahrain` | Bahrain |

## CI/CD Integration

### GitHub Actions
```yaml
- name: Run k6 Cloud Test
  uses: grafana/k6-action@v0.3.1
  with:
    filename: tests/load.js
    cloud: true
    token: ${{ secrets.K6_CLOUD_TOKEN }}
```

### GitLab CI
```yaml
k6-cloud:
  image: grafana/k6
  script:
    - k6 cloud login --token $K6_CLOUD_TOKEN
    - k6 cloud tests/load.js
  only:
    - main
```

### CircleCI
```yaml
- run:
    name: Run k6 Cloud Test
    command: |
      k6 cloud login --token $K6_CLOUD_TOKEN
      k6 cloud tests/load.js
```

## REST API

```bash
BASE=https://api.k6.io/v3
TOKEN=your-token

# List projects
curl $BASE/projects -H "Authorization: Token $TOKEN"

# List test runs for a project
curl "$BASE/projects/{projectId}/test-runs" -H "Authorization: Token $TOKEN"

# Get test run details + results
curl "$BASE/runs/{runId}" -H "Authorization: Token $TOKEN"

# Get metrics for a run
curl "$BASE/runs/{runId}/metrics" -H "Authorization: Token $TOKEN"

# Stop a running test
curl -X POST "$BASE/runs/{runId}/stop" -H "Authorization: Token $TOKEN"

# Create a scheduled test
curl -X POST "$BASE/projects/{projectId}/schedules" \
  -H "Authorization: Token $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Nightly load test",
    "script_id": 123,
    "cron": "0 2 * * *",
    "timezone": "UTC"
  }'
```

## Test Authoring Tools

- **k6 Studio** — desktop GUI for recording, building, and running k6 tests
- **Browser recorder** — Chrome extension that records user journeys as k6 scripts
- **Test builder** — drag-and-drop scenario builder in Grafana Cloud UI (no code required)
- **k6 TypeScript template** — starter template with TypeScript support and type definitions

## Result Analysis

```bash
# View results summary after cloud run
k6 cloud --results-id {runId}

# Export results as JSON
k6 cloud --results-export results.json
```

In the Cloud UI:
- **Performance Overview**: VUs, request rate, error rate, response time over time
- **Checks tab**: pass/fail rates per check, by time
- **Thresholds**: pass/fail status for each threshold
- **Logs tab**: console.log output from VUs
- **Comparison**: overlay multiple test runs to spot regressions

## When to Use Each Tool

| Scenario | Use |
|----------|-----|
| External uptime monitoring, always-on | Synthetic Monitoring |
| Scheduled lightweight API health checks | Synthetic Monitoring |
| Load testing before a release | k6 Cloud |
| Stress testing to find limits | k6 Cloud |
| Performance regression in CI/CD | k6 Cloud |
| Real user monitoring (browser) | Faro / Frontend Observability |
