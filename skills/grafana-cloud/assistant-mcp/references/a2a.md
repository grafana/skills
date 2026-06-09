# Grafana Assistant A2A (Agent-to-Agent)

The Grafana Assistant supports the Agent-to-Agent (A2A) protocol for programmatic agent integration. External agents discover Grafana agents via the standard Agent Card endpoint:

```
GET https://<GRAFANA_ASSISTANT_HOST>/.well-known/agent.json
```

Returns an Agent Card describing the supervisor agent's capabilities. Use this when building agents that need to delegate observability reasoning (e.g. a multi-agent system where one agent specializes in Grafana queries while another handles other domains).

This is distinct from the MCP server in the parent skill:

| MCP server | A2A protocol |
|---|---|
| Direct tool access — agent calls `query_prometheus` etc. | Agent delegates a higher-level task ("investigate the spike") to the Assistant |
| Caller does its own reasoning | Assistant does the reasoning, returns a synthesized answer |
| `stdio` or SSE transport | HTTP, well-known endpoint |

For most coding-agent integration, MCP is what you want. A2A is for orchestrator agents delegating to specialized Assistant agents.
