---
name: testing
license: Apache-2.0
description: Probe, load-test, and instrument frontends from Grafana Cloud. Covers Synthetic Monitoring (HTTP / DNS / TCP / Ping / Traceroute / Multihttp / k6-browser scripted checks from 20+ global probes, alert on `probe_success` + TLS-cert expiry), Grafana Cloud k6 (distributed load tests across AWS load-zones, scenarios, `http_req_duration` thresholds, CI integration via `grafana/k6-action`), and Frontend Observability with Faro Web SDK (RUM, Core Web Vitals, custom events, `pushError`, distributed-trace correlation). Use when checking website / API uptime from multiple regions, gating a release on a load test, watching for TLS-cert renewal, instrumenting a React/Vue app, tracking Core Web Vitals, or correlating frontend errors to backend traces — even when the user says "is my login flow up?", "monitor my API", "ping our endpoint every minute", "release-gate load test", "browser performance monitoring", "session replay", or "RUM" without naming Synthetic Monitoring / k6 / Faro.
---

# Grafana Cloud Testing

> **Docs**: https://grafana.com/docs/grafana-cloud/testing/

Three pillars: external probing (Synthetic Monitoring), load testing (k6 Cloud), real-user monitoring (Faro).

## Prerequisites

- Grafana Cloud stack
- Synthetic Monitoring: SM access token (`sm:write`)
- k6 Cloud: a Grafana Cloud k6 token + projectID
- Faro: a Faro app + write-token from **Frontend Observability → Apps**

## Common Workflows

### 1. Create + verify a Synthetic HTTP check

```bash
# 1. Create the check (full payload in references/synthetic.md)
curl -X POST https://synthetic-monitoring-api.grafana.net/sm/checks \
  -H "Authorization: Bearer <sm-token>" -H "Content-Type: application/json" \
  -d '{"job":"website","target":"https://example.com","frequency":60000,"timeout":15000,
       "enabled":true,"probes":[1,5,10],
       "settings":{"http":{"method":"GET","validStatusCodes":[200]}}}'

# 2. List checks — confirm it exists and is enabled
curl -s https://synthetic-monitoring-api.grafana.net/sm/checks \
  -H "Authorization: Bearer <sm-token>" | jq '.[] | select(.job=="website")'

# 3. Verify probe_success arrived (wait ~60s for the first run)
#    In Grafana Explore on the synthetic metrics datasource:
#      probe_success{job="website"}
#    Expect 1 from each probe in `probes:[1,5,10]`.
#
# Rollback: DELETE /sm/checks/<id> or set `"enabled": false`.
```

See [`references/synthetic.md`](references/synthetic.md) for all check types, PromQL queries, and alert rules.

### 2. Run a k6 cloud load test

```bash
# 1. Authenticate once
k6 cloud login --token <grafana-cloud-k6-token>

# 2. Validate the script locally first (smoke run, no cloud cost)
k6 run --vus 1 --duration 30s script.js

# 3. Launch in cloud
k6 cloud script.js
# → URL of the run; thresholds (p95<500ms, error<1%) decide pass/fail.

# 4. Verify in CI — exit code 0 = thresholds passed, 99 = threshold failed.
echo $?
```

Full script + scenarios + CI YAML: [`references/k6-and-faro.md`](references/k6-and-faro.md).

### 3. Instrument a frontend with Faro

```bash
# 1. Install
npm install @grafana/faro-web-sdk @grafana/faro-web-tracing
```

```javascript
// 2. initializeFaro({ url, apiKey, app, instrumentations }) — see references/k6-and-faro.md
// 3. Push a test event so we have something to look for:
faro.api.pushEvent('faro_smoketest', { ts: Date.now().toString() });
```

```bash
# 4. Verify the collector accepted it (browser DevTools → Network)
#    POST to /collect should return 202. If 401 — apiKey mismatch.

# 5. Verify in Grafana
#    - Frontend Observability → your app → Sessions: should show your session
#    - Explore on Loki: `{kind="event"} |= "faro_smoketest"`
#    - For traces: filter by `service.name="my-frontend"` in Tempo
```

## Troubleshooting

- Synthetic check stuck at `probe_success=0` → check `probe_*_duration_seconds` for the failing stage; the probe-region label tells you which prober errored
- k6 cloud run "ABORTED_THRESHOLD" → a threshold tripped; inspect the run page to see which one
- Faro events not landing → check the browser network call to `/collect` returns 202; common cause is wrong `apiKey` or `url` (must match the FE Observability app)

## References

- [`references/synthetic.md`](references/synthetic.md) — Synthetic Monitoring essentials: check types, key PromQL metrics, alert rules
- [`references/synthetic-monitoring.md`](references/synthetic-monitoring.md) — deep dive: full API for check CRUD, probe selection, scripted (k6) checks, multi-step browser checks
- [`references/k6-and-faro.md`](references/k6-and-faro.md) — k6 cloud script + Faro Web SDK init snippets for end-to-end testing
- [`references/k6-cloud.md`](references/k6-cloud.md) — deep dive: k6 cloud config (project + load zones + thresholds), CI integration, run analysis

## Resources

- [Synthetic Monitoring docs](https://grafana.com/docs/grafana-cloud/testing/synthetic-monitoring/)
- [Grafana Cloud k6 docs](https://grafana.com/docs/grafana-cloud/testing/k6/)
- [Faro / Frontend Observability docs](https://grafana.com/docs/grafana-cloud/monitor-applications/frontend-observability/)
