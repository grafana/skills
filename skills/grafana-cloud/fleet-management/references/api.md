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
