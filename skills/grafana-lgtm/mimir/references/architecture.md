# Mimir architecture & API

## Write path

Client → Distributor → Ingester (WAL) → Object Storage (blocks)

## Read path

Client → Query-frontend (cache/sharding) → Query-scheduler → Querier ← Store-gateway

## Components

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

## HTTP API

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | /api/v1/push | Prometheus remote write |
| POST | /otlp/v1/metrics | OTLP ingestion |
| GET | /api/v1/query | Instant PromQL query |
| GET | /api/v1/query_range | Range PromQL query |
| GET | /api/v1/labels | List labels |
| GET | /api/v1/series | List series |
| GET | /api/v1/rules | List rules |
| GET | /ready | Readiness probe |
| GET | /metrics | Self metrics |

## Deployment modes

```bash
# Monolithic — single binary, all targets
mimir -config.file=mimir.yaml -target=all

# Read-Write split
mimir -target=write    # distributor + ingester
mimir -target=read     # query-frontend + querier
mimir -target=backend  # store-gateway + compactor + ruler

# Microservices — each target as a separate deployment
```

## Common limits

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
