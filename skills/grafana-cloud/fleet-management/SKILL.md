---
name: fleet-management
license: Apache-2.0
description: Manage a fleet of Grafana Alloy collectors with Fleet Management — author Alloy pipelines once, target them via attribute matchers (`env="production"`, regex `region=~"us-.*"`), push remotely via OpAMP without restarting collectors. Covers pipeline create / update / matcher RPCs, collector attribute API, `remotecfg` bootstrap block (standalone + Helm), pre-deploy `alloy fmt` validation, the local Alloy UI at port 12345 for component health, and post-deploy `REMOTE_CONFIG_STATUS_APPLIED` verification. Use when standing up a Cloud Alloy fleet, pushing a config change to 200 collectors, hunting why one collector shows `REMOTE_CONFIG_STATUS_FAILED`, validating River syntax before saving, or wiring `discovery.kubernetes` → `prometheus.remote_write` — even when the user says "configure Alloy", "remote config the collectors", "push pipeline", "OpAMP", "collector is unhealthy", or "manage agent config centrally" without naming Fleet Management.
---

# Grafana Fleet Management + Alloy Configuration

> **Docs**: https://grafana.com/docs/grafana-cloud/send-data/fleet-management/

Remote pipeline distribution to Alloy collectors via OpAMP — author once, target with matchers, hot-apply (no restart).

## Prerequisites

- Grafana Cloud stack with Fleet Management enabled
- API token with Fleet Management access (`Authorization: Bearer <STACK_ID>:<TOKEN>`)
- Alloy ≥ 1.0 installed on the targets (standalone or via `grafana/alloy` Helm chart)
- `alloy` CLI locally for `alloy fmt` syntax validation

## Concepts

- **Collector** — Alloy instance with unique ID + attributes
- **Pipeline** — named Alloy River config stored in Fleet Management
- **Matcher** — selector mapping a pipeline to collectors by attribute
- **Attributes** — key/value labels on a collector (`env`, `team`, `region`)

## Common Workflows

### 1. Author + validate + deploy a pipeline

```bash
# 1. Save the pipeline to a local file (lint catches typos before remote)
cat > pipeline.alloy <<'EOF'
prometheus.scrape "default" {
  targets    = []
  forward_to = [prometheus.remote_write.grafana_cloud.receiver]
  scrape_interval = "60s"
}

prometheus.remote_write "grafana_cloud" {
  endpoint {
    url = "https://prometheus-prod-01-eu-west-0.grafana.net/api/prom/push"
    basic_auth {
      username = "<METRICS_USERNAME>"
      password = env("GRAFANA_CLOUD_API_KEY")
    }
  }
}
EOF

# 2. Validate syntax LOCALLY before sending to Fleet Management
alloy fmt pipeline.alloy            # rewrites in place or errors with line number
alloy validate pipeline.alloy       # full semantic check (newer Alloy releases)

# 3. Create the pipeline via API (see references/api.md for the payload schema)
BASE=https://fleet-management-prod-us-east-0.grafana.net
TOKEN=<STACK_ID>:<API_TOKEN>
PAYLOAD=$(jq -n --rawfile c pipeline.alloy '{
  name:"k8s-metrics", contents:$c,
  matchers:[{name:"env",value:"production",type:"EQUAL"}]
}')
curl -s -X POST "$BASE/pipeline.v1.PipelineService/CreatePipeline" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$PAYLOAD" | jq

# 4. Verify it rolled out — every targeted collector should report APPLIED within 1-2 polls
curl -s -X POST "$BASE/collector.v1.CollectorService/ListCollectors" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{}' \
  | jq '.collectors[] | select(.attributes[]?.value=="production")
        | {name, remoteConfigStatus}'
# Expect every row: remoteConfigStatus == "REMOTE_CONFIG_STATUS_APPLIED"
```

### 2. Troubleshoot a `REMOTE_CONFIG_STATUS_FAILED` collector

```bash
# 1. Find failed collectors and surface the error message
curl -s -X POST "$BASE/collector.v1.CollectorService/ListCollectors" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{}' \
  | jq '.collectors[] | select(.remoteConfigStatus=="REMOTE_CONFIG_STATUS_FAILED")
        | {name, msg:.remoteConfigStatusMessage}'

# 2. Re-validate the offending pipeline locally
alloy fmt pipeline.alloy

# 3. Inspect Alloy directly — UI at port 12345 shows per-component health
#    http://<COLLECTOR_HOST>:12345 → Graph / Components / Clustering tabs
kubectl -n monitoring logs -l app.kubernetes.io/name=alloy --tail=100 | grep -iE 'remote|error'

# 4. After fixing + re-pushing, re-list collectors and confirm the row flips to APPLIED.
```

Failure-message decoder table: [`references/api.md`](references/api.md).

### 3. Onboard a new Alloy with the bootstrap block

The bootstrap `remotecfg` block is the only local config required:

```alloy
remotecfg {
  url = "https://<FLEET_MANAGEMENT_HOST>"
  basic_auth { username = "<STACK_ID>"; password = env("GRAFANA_CLOUD_API_KEY") }
  poll_frequency = "1m"
  attributes = { "env" = env("ENVIRONMENT"), "team" = "platform" }
}
```

```bash
# Verify after start
curl -s http://localhost:12345/api/v0/web/components \
  | jq '.[] | select(.id=="remotecfg") | {id, health:.health.state}'
# health.state == "healthy"
```

Full bootstrap (standalone + Helm) + Assistant tool list: [`references/bootstrap.md`](references/bootstrap.md).

## Resources

- [Fleet Management docs](https://grafana.com/docs/grafana-cloud/send-data/fleet-management/)
- [Alloy components](https://grafana.com/docs/alloy/latest/reference/components/)
- [OpAMP spec](https://github.com/open-telemetry/opamp-spec)
