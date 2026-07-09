# Fleet Management API

Endpoints are gRPC-Web — `POST` JSON to `<host>/<service>.<RPC>`.

```bash
BASE=https://fleet-management-prod-us-east-0.grafana.net
TOKEN=<STACK_ID>:<API_TOKEN>
```

## Collectors

```bash
# List all collectors + health
curl -s -X POST "$BASE/collector.v1.CollectorService/ListCollectors" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{}' | jq '.collectors[] | {id, name, remoteConfigStatus}'

# Update collector attributes (matchers target these)
curl -s -X POST "$BASE/collector.v1.CollectorService/UpdateCollector" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "id": "<COLLECTOR_ID>",
    "attributes": [
      {"name":"env",   "value":"production"},
      {"name":"team",  "value":"platform"},
      {"name":"region","value":"us-east-1"}
    ]
  }'
```

Auto-set attributes on registration: `platform`, `arch`, `alloy_version`.

## Pipelines

```bash
# List
curl -s -X POST "$BASE/pipeline.v1.PipelineService/ListPipelines" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{}'

# Create (plain-text Alloy config, not base64)
curl -s -X POST "$BASE/pipeline.v1.PipelineService/CreatePipeline" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "name": "k8s-metrics",
    "contents": "prometheus.scrape \"default\" {\n  targets = []\n  forward_to = []\n}",
    "matchers": [{"name":"env","value":"production","type":"EQUAL"}]
  }'

# Update — set matchers
curl -s -X POST "$BASE/pipeline.v1.PipelineService/UpdatePipeline" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "id":"<PIPELINE_ID>",
    "matchers": [
      {"name":"env","value":"production","type":"EQUAL"},
      {"name":"team","value":"platform","type":"EQUAL"}
    ]
  }'
```

Matcher `type` values: `EQUAL`, `NOT_EQUAL`, `REGEX`, `NOT_REGEX`.
A pipeline with no matchers is saved but deployed to zero collectors.

## Matcher selector syntax (UI form)

| Op | Example | Meaning |
|----|---------|---------|
| `=`  | `env="production"` | Exact match |
| `!=` | `env!="dev"` | Not equal |
| `=~` | `region=~"us-.*"` | Regex match |
| `!~` | `region!~"eu-.*"` | Regex not match |

## Alloy component categories

| Category | Example components |
|----------|--------------------|
| Discovery | `discovery.kubernetes`, `discovery.docker`, `discovery.relabel` |
| Metrics   | `prometheus.scrape`, `prometheus.remote_write`, `prometheus.operator.*` |
| Logs      | `loki.source.file`, `loki.source.kubernetes`, `loki.write` |
| Traces    | `otelcol.receiver.otlp`, `otelcol.exporter.otlp` |
| Profiles  | `pyroscope.scrape`, `pyroscope.write` |
| Transform | `otelcol.processor.batch`, `otelcol.processor.filter` |

## Common failure messages

| Status message | Root cause | Fix |
|---|---|---|
| `syntax error at line N` | Invalid River syntax | Run `alloy fmt` before saving |
| `component not found: X` | Alloy version too old | Upgrade Alloy |
| `failed to unmarshal config` | Encoding error in API call | Send plain text, not base64 |
| `authentication failed` | Wrong token | Rotate and re-apply |
| `connection refused` | Network/firewall | Open egress to Fleet Management host |
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

## Matcher Types (API form)

When constructing the JSON payload (vs the UI selector syntax above), the API expects the enum form:

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
