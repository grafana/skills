# SSE transport — for team sharing or VS Code

Default transport is `stdio` (agent spawns the server as a subprocess). For shared / long-lived servers, run as SSE.

## Run as SSE server

```bash
GRAFANA_URL=https://myorg.grafana.net \
GRAFANA_API_KEY=glsa_xxxx \
mcp-grafana --transport sse --port 3001
```

Point agents at `http://localhost:3001/sse`.

## VS Code MCP extension config

In `settings.json`:

```json
{
  "mcp.servers": {
    "grafana": {
      "type": "sse",
      "url": "http://localhost:3001/sse"
    }
  }
}
```

## When to pick SSE over stdio

| stdio | SSE |
|---|---|
| Single user, single machine | Multiple users / shared dev container |
| Agent spawns + tears down per session | Long-lived server, multiple agents connect |
| Credentials live in agent config | Credentials live in the SSE process env |

## Common failure modes

| Symptom | Likely cause |
|---|---|
| Agent can't reach `http://localhost:3001/sse` | Server isn't running, or port conflict — `lsof -i :3001` |
| 401 on every tool call | `GRAFANA_API_KEY` wasn't passed to the SSE process env |
| SSE connection drops after a few minutes | Firewall / proxy timing out idle HTTP streams — set keep-alive on the proxy |
