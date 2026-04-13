# Fleet Management API Reference

Base URL: `https://fleet-management-prod-<region>.grafana.net`

Authentication: `Authorization: Bearer <grafana-cloud-api-key>`

## Collector API

```bash
BASE=https://fleet-management-prod-us-east-0.grafana.net
TOKEN=your-api-key

# List collectors (with optional attribute filters)
curl -X POST $BASE/collector.v1.CollectorService/ListCollectors \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"attributes": [{"name": "env", "value": "production"}]}'

# Get a single collector
curl -X POST $BASE/collector.v1.CollectorService/GetCollector \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"id": "collector-id"}'

# Update collector attributes
curl -X POST $BASE/collector.v1.CollectorService/UpdateCollector \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"id": "collector-id", "attributes": [{"name": "env", "value": "staging"}]}'

# Bulk update multiple collectors
curl -X POST $BASE/collector.v1.CollectorService/BulkUpdateCollectors \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ids": ["id-1", "id-2"], "attributes": [{"name": "maintenance", "value": "true"}]}'

# Delete a collector
curl -X POST $BASE/collector.v1.CollectorService/DeleteCollector \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"id": "collector-id"}'

# Bulk delete collectors
curl -X POST $BASE/collector.v1.CollectorService/BulkDeleteCollectors \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"ids": ["id-1", "id-2"]}'

# List all attribute keys/values across the fleet
curl -X POST $BASE/collector.v1.CollectorService/ListCollectorAttributes \
  -H "Authorization: Bearer $TOKEN" -d '{}'
```

## Pipeline API

```bash
# List pipelines
curl -X POST $BASE/pipeline.v1.PipelineService/ListPipelines \
  -H "Authorization: Bearer $TOKEN" -d '{}'

# Create a pipeline
curl -X POST $BASE/pipeline.v1.PipelineService/CreatePipeline \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "production-metrics",
    "matchers": [
      {"name": "env", "value": "production", "type": "EQUAL"},
      {"name": "region", "value": "us-.*", "type": "REGEX"}
    ],
    "contents": "prometheus.remote_write \"cloud\" {\n  endpoint { url = \"...\" }\n}"
  }'

# Update a pipeline (creates a new revision)
curl -X POST $BASE/pipeline.v1.PipelineService/UpdatePipeline \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"id": "pipeline-id", "contents": "# Updated\n...", "matchers": [...]}'

# Upsert (create or update by name — idempotent)
curl -X POST $BASE/pipeline.v1.PipelineService/UpsertPipeline \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "production-metrics", "matchers": [...], "contents": "..."}'

# Delete a pipeline
curl -X POST $BASE/pipeline.v1.PipelineService/DeletePipeline \
  -H "Authorization: Bearer $TOKEN" -d '{"id": "pipeline-id"}'

# Bulk delete pipelines
curl -X POST $BASE/pipeline.v1.PipelineService/BulkDeletePipelines \
  -H "Authorization: Bearer $TOKEN" -d '{"ids": ["id-1", "id-2"]}'

# Force immediate sync to specific collectors (bypasses poll interval)
curl -X POST $BASE/pipeline.v1.PipelineService/SyncPipelines \
  -H "Authorization: Bearer $TOKEN" -d '{"collectorIds": ["collector-id"]}'
```

## Pipeline Revision History

Every `UpdatePipeline` call creates a new revision:

```bash
# List revisions
curl -X POST $BASE/pipeline.v1.PipelineService/ListPipelineRevisions \
  -H "Authorization: Bearer $TOKEN" -d '{"pipelineId": "pipeline-id"}'

# Roll back to a previous revision
curl -X POST $BASE/pipeline.v1.PipelineService/RollbackPipeline \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"pipelineId": "pipeline-id", "revisionId": "revision-id"}'
```

## Tenant API

Returns rate limits and quotas for your Fleet Management tenant:

```bash
curl -X POST $BASE/tenant.v1.TenantService/GetLimits \
  -H "Authorization: Bearer $TOKEN" -d '{}'

# Response:
# {
#   "maxCollectors": 1000,
#   "maxPipelines": 100,
#   "maxPipelineSizeBytes": 1048576,
#   "maxMatchersPerPipeline": 10
# }
```

## Matcher Types

| Type | Description | Example value |
|------|-------------|---------------|
| `EQUAL` | Exact match | `"production"` |
| `NOT_EQUAL` | Not equal | `"dev"` |
| `REGEX` | RE2 regex match | `"us-.*"` |
| `NOT_REGEX` | Does not match regex | `"eu-.*"` |

## remotecfg Block (Alloy)

```alloy
remotecfg {
  url = "https://fleet-management-prod-us-east-0.grafana.net"

  basic_auth {
    username = sys.env("FM_INSTANCE_ID")   // Stack ID / instance ID
    password = sys.env("FM_API_KEY")
  }

  // Attributes used to match pipeline matchers
  attributes = {
    "env"    = "production",
    "region" = "us-east-1",
    "team"   = "platform",
  }

  poll_interval = "1m"   // How often to check for config updates
  id            = ""     // Auto-generated; persist across restarts for stable ID
}
```

## Advanced Patterns

### Staged Rollout

```bash
# 1. Create canary pipeline targeting one collector by attribute
POST .../CreatePipeline
{ "name": "canary-v2",
  "matchers": [{"name": "canary", "value": "true", "type": "EQUAL"}],
  "contents": "# New config v2..." }

# 2. Add canary=true attribute to test collector
POST .../UpdateCollector
{ "id": "collector-id", "attributes": [{"name": "canary", "value": "true"}] }

# 3. Validate metrics; expand to more collectors
# 4. Update main pipeline, remove canary pipeline
```

### On-Demand Debug Pipeline

```bash
# Temporarily boost log verbosity for one collector
POST .../CreatePipeline
{ "name": "debug-001",
  "matchers": [{"name": "id", "value": "collector-001", "type": "EQUAL"}],
  "contents": "logging { level = \"debug\" }" }
# Delete when done
```

### Kubernetes DaemonSet with Auto-Attributes

```yaml
# Pass K8s metadata as env vars to Alloy
env:
  - name: K8S_NODE_NAME
    valueFrom: { fieldRef: { fieldPath: spec.nodeName } }
  - name: K8S_NAMESPACE
    valueFrom: { fieldRef: { fieldPath: metadata.namespace } }
```

```alloy
remotecfg {
  url = sys.env("FM_URL")
  basic_auth {
    username = sys.env("FM_INSTANCE_ID")
    password = sys.env("FM_API_KEY")
  }
  attributes = {
    "k8s.node.name" = sys.env("K8S_NODE_NAME"),
    "k8s.namespace" = sys.env("K8S_NAMESPACE"),
    "env"           = "production",
  }
}
```
