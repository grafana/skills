---
name: mimir
license: Apache-2.0
description: Stand up Grafana Mimir for horizontally scalable, multi-tenant, long-term Prometheus + OTLP metrics storage. Covers monolithic / read-write / microservices deployment, S3 / GCS / Azure / filesystem block storage, Prometheus `remote_write` and OTLP ingestion, multi-tenancy with `X-Scope-OrgID`, ingester replication factor, compactor retention, and per-tenant limits. Use when running Mimir locally or on Kubernetes (Helm `mimir-distributed`), scaling Prometheus past a single node, picking ingest / query / backend split, configuring tenants and ingestion rate, debugging `/ready` 503s or `429 Too Many Requests`, or pointing Grafana at a Mimir datasource — even when the user says "I need long-term Prometheus storage", "scale Prometheus", "multi-tenant metrics backend", "Cortex replacement", "remote_write target", or "store 10M active series" without naming Mimir.
---

# Grafana Mimir

> **Docs**: https://grafana.com/docs/mimir/latest/

Horizontally scalable, multi-tenant, long-term storage for Prometheus + OpenTelemetry metrics.

## Prerequisites

- Docker (for quick start) or a Kubernetes cluster (for Helm)
- An object-storage bucket for production (S3/GCS/Azure) — filesystem only for dev
- Prometheus or Alloy able to remote_write to the Mimir push endpoint

## Common Workflows

### 1. Stand up monolithic Mimir locally

```yaml
# demo.yaml
target: all
multitenancy_enabled: false

blocks_storage:
  backend: filesystem
  bucket_store:
    sync_dir: /tmp/mimir/tsdb-sync
  filesystem:
    dir: /tmp/mimir/data/tsdb
  tsdb:
    dir: /tmp/mimir/tsdb

compactor:
  data_dir: /tmp/mimir/compactor
  sharding_ring:
    kvstore: { store: memberlist }

distributor:
  ring:
    instance_addr: 127.0.0.1
    kvstore: { store: memberlist }

ingester:
  ring:
    instance_addr: 127.0.0.1
    kvstore: { store: memberlist }
    replication_factor: 1

server:
  http_listen_port: 9009
  grpc_listen_port: 9095
  log_level: error
```

```bash
# 1. Run it
docker run --rm -p 9009:9009 -v $(pwd)/demo.yaml:/etc/mimir/demo.yaml \
  grafana/mimir:latest --config.file=/etc/mimir/demo.yaml

# 2. Verify readiness (expect HTTP 200, body: "ready")
curl -sf http://localhost:9009/ready

# 3. Verify it's serving the API
curl -s http://localhost:9009/api/v1/labels | jq '.status'   # → "success"

# 4. Verify self-metrics scrape
curl -s http://localhost:9009/metrics | grep -E '^mimir_(distributor|ingester)_' | head
```

### 2. Send metrics — Prometheus remote_write

```yaml
remote_write:
  - url: http://localhost:9009/api/v1/push
    headers:
      X-Scope-OrgID: tenant1   # required when multitenancy_enabled: true
```

```bash
# Verify samples are landing
curl -s -H 'X-Scope-OrgID: tenant1' \
  'http://localhost:9009/api/v1/query?query=up' | jq '.data.result | length'
# Expect > 0 within ~30s of Prometheus scraping
```

### 3. Send metrics — Grafana Alloy

```alloy
prometheus.remote_write "mimir" {
  endpoint {
    url = "http://mimir:9009/api/v1/push"
    headers = { "X-Scope-OrgID" = "tenant1" }
  }
}
```

### 4. Deploy on Kubernetes (Helm, microservices)

```bash
# 1. Install
helm repo add grafana https://grafana.github.io/helm-charts
helm install mimir grafana/mimir-distributed --version 6.0.6 -f values.yaml

# 2. Verify every pod is Running / Ready
kubectl get pods -n mimir
#   distributor, ingester, querier, query-frontend, store-gateway, compactor, ruler

# 3. Verify the gateway is ready
kubectl port-forward -n mimir svc/mimir-nginx 9009:80 &
curl -sf http://localhost:9009/ready
```

## Multi-tenancy

```yaml
multitenancy_enabled: true
# Every request must include header:  X-Scope-OrgID: <tenant-id>
```

For storage backends (S3 / GCS / Azure / filesystem) see [`references/storage.md`](references/storage.md). For component roles, ring options, limits, and API endpoint dumps see [`references/architecture.md`](references/architecture.md).

## Troubleshooting

- `/ready` returns 503 → ingester still joining ring; check `mimir_ring_members` and ingester logs
- `429 Too Many Requests` on push → bump `limits.ingestion_rate` / `ingestion_burst_size`
- Samples written but query returns empty → confirm `X-Scope-OrgID` matches between write and read
- Query for old data returns nothing → check compactor logs and that store-gateway has synced blocks

## Resources

- [Mimir docs](https://grafana.com/docs/mimir/latest/)
- [Helm chart `mimir-distributed`](https://github.com/grafana/mimir/tree/main/operations/helm/charts/mimir-distributed)
- [Architecture reference](https://grafana.com/docs/mimir/latest/references/architecture/)
