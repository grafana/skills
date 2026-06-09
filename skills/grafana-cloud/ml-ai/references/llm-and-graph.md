# LLM Plugin, Assistant, Knowledge Graph

## Grafana Assistant — capabilities

- Convert natural language to PromQL / LogQL / TraceQL
- Explain existing queries in plain English
- Build / edit dashboards from descriptions
- Investigate incidents (correlate metrics, logs, traces)
- MCP server integration for external tools
- RBAC controls per organization
- Slack integration for on-call workflows

**Assistant Investigations** (public preview): multi-agent autonomous incident analysis — launches multiple specialized agents in parallel.

**Enable:** Grafana Cloud → Administration → AI & LLM → Enable Grafana Assistant
**In panel editor:** click the magic-wand "Assistant" icon for query suggestions.

## LLM Plugin

Authenticated proxy for LLM provider API calls from Grafana panels and plugins.

**Supported providers:** OpenAI, Anthropic (Claude), Azure OpenAI, vLLM, Ollama, LiteLLM
**Powers:** flame-graph interpretation, incident auto-summary, panel title generation, Sift log explanations, natural-language panel descriptions.
**Enable:** Administration → Plugins → LLM Plugin → "Enable OpenAI/LLM access via Grafana"

```yaml
# provisioning/plugins/llm.yaml
apiVersion: 1
apps:
  - type: grafana-llm-app
    jsonData:
      openAIUrl: https://api.openai.com
      openAIModel: gpt-4o
      # Anthropic alternative:
      # provider: anthropic
      # anthropicModel: claude-sonnet-4-6
      # Azure OpenAI alternative:
      # openAIUrl: https://your-resource.openai.azure.com
      # azureModelMapping: '[["gpt-4o","your-deployment-name"]]'
    secureJsonData:
      openAIKey: sk-your-openai-key
```

## Knowledge Graph

Auto-discovers services, pods, nodes, namespaces from metric labels + trace data. Updates every minute.

**Access:** Observability → Entity graph

**Search:**
```
Show Service api-server
Show all services in namespace production
Show Pod frontend-abc123
```

**RCA Workbench:** structured troubleshooting on top of the graph — traces entity relationships for blast-radius / upstream-cause analysis.

## Adaptive Metrics recommendations

```bash
curl https://<stack>.grafana.net/api/plugins/grafana-adaptive-metrics-app/resources/v1/recommendations \
  -H "Authorization: Bearer <token>"
```

Sample rule that drops high-cardinality labels:

```yaml
- match: "^http_request_duration_seconds.*"
  action: keep
  match_labels: [method, status, service]
  # Drops: pod, container, instance
```
