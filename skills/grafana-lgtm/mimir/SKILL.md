---
name: mimir
license: Apache-2.0
description: >
  Grafana Mimir scalable long-term metrics storage. Covers architecture (distributor/ingester/compactor/querier/
  query-frontend/store-gateway/ruler), deployment modes (monolithic/microservices), configuration, Prometheus
  remote write, PromQL querying, multi-tenancy, compaction, and operations. Use when working with Mimir for
  metrics storage, scaling Prometheus, configuring Mimir clusters, writing PromQL, or debugging Mimir.
---

# Grafana Mimir

> **Docs**: https://grafana.com/docs/mimir/latest/

Horizontally scalable, highly available, multi-tenant, long-term storage for Prometheus and OpenTelemetry metrics.

## Quick Start (Monolithic Mode)

```yaml
# demo.yaml - single binary, no external dependencies
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
    kvstore:
      store: memberlist

distributor:
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: memberlist

ingester:
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: memberlist
    replication_factor: 1

server:
  http_listen_port: 9009
  grpc_listen_port: 9095
  log_level: error
```

```bash
docker run --rm -p 9009:9009 -v $(pwd)/demo.yaml:/etc/mimir/demo.yaml \
  grafana/mimir:latest --config.file=/etc/mimir/demo.yaml
```

## Sending Metrics to Mimir

### Prometheus remote_write
```yaml
remote_write:
  - url: http://localhost:9009/api/v1/push
    headers:
      X-Scope-OrgID: tenant1
```

### Grafana Alloy
```alloy
prometheus.remote_write "mimir" {
  endpoint {
    url = "http://mimir:9009/api/v1/push"
    headers = { "X-Scope-OrgID" = "tenant1" }
  }
}
```

## Multi-tenancy

```yaml
multitenancy_enabled: true
# All requests require: X-Scope-OrgID: <tenant-id>
```

## Architecture

### Write Path
Client → Distributor → Ingester (WAL) → Object Storage (blocks)

### Read Path
Client → Query-frontend (cache/sharding) → Query-scheduler → Querier ← Store-gateway

### Components

| Component | Role |
|-----------|------|
| **Distributor** | Validates & routes incoming samples via hash ring |
| **Ingester** | In-memory storage, WAL, flushes blocks to object store |
| **Compactor** | Merges blocks, enforces retention |
| **Querier** | Executes PromQL across ingesters + object store |
| **Query-frontend** | Request splitting, caching, parallelization |
| **Store-gateway** | Provides access to blocks in object storage |
| **Ruler** | Evaluates recording and alerting rules |
| **Alertmanager** | Routes and deduplicates alerts |

## Storage Configuration

### S3
```yaml
blocks_storage:
  backend: s3
  s3:
    bucket_name: mimir-blocks
    endpoint: s3.us-east-1.amazonaws.com
    region: us-east-1
    access_key_id: ${AWS_ACCESS_KEY_ID}
    secret_access_key: ${AWS_SECRET_ACCESS_KEY}
```

### GCS
```yaml
blocks_storage:
  backend: gcs
  gcs:
    bucket_name: mimir-blocks
```

### Azure
```yaml
blocks_storage:
  backend: azure
  azure:
    account_name: storageaccountname
    account_key: ${AZURE_STORAGE_KEY}
    container_name: mimir-blocks
```

## Deployment Modes

```bash
# Monolithic
mimir -config.file=mimir.yaml -target=all

# Kubernetes (Helm)
helm repo add grafana https://grafana.github.io/helm-charts
helm install mimir grafana/mimir-distributed -f values.yaml

# Read-Write mode
mimir -target=write    # distributor + ingester
mimir -target=read     # query-frontend + querier
mimir -target=backend  # store-gateway + compactor + ruler
```

## Key Configuration Options

```yaml
limits:
  ingestion_rate: 10000
  ingestion_burst_size: 200000
  max_global_series_per_user: 1500000
  max_label_names_per_series: 30
  compactor_blocks_retention_period: 30d
  ruler_max_rules_per_rule_group: 20

ingester:
  ring:
    replication_factor: 3

querier:
  max_concurrent: 20

frontend:
  max_outstanding_per_tenant: 100
  compress_responses: true
```

## HTTP API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | /api/v1/push | Remote write |
| POST | /otlp/v1/metrics | OTLP ingestion |
| GET | /api/v1/query | Instant PromQL query |
| GET | /api/v1/query_range | Range PromQL query |
| GET | /api/v1/labels | List labels |
| GET | /api/v1/series | List series |
| GET | /api/v1/rules | List rules |
| GET | /ready | Readiness probe |
| GET | /metrics | Self metrics |
