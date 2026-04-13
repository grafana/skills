---
name: assistant-mcp
license: Apache-2.0
description:
  Connect AI coding agents (Claude Code, Cursor, VS Code, OpenAI Codex) to Grafana Cloud via
  the Model Context Protocol (MCP) server. Use when the user asks to connect Claude Code to
  Grafana, set up MCP for Grafana, use Grafana tools in Cursor, query Grafana from an AI agent,
  configure the Grafana MCP server, or make AI agents interact with Grafana Cloud APIs. Triggers
  on phrases like "MCP server", "connect Claude Code to Grafana", "Grafana MCP", "AI agent
  Grafana", "Claude Grafana tools", "Cursor Grafana", or "agent observability".
---

# Grafana Cloud MCP Server Setup

The Grafana MCP server exposes Grafana Cloud capabilities as tools that AI agents can call via
the Model Context Protocol. Once connected, agents can query metrics, search dashboards, manage
alerts, investigate incidents, and interact with Fleet Management - all without leaving their
coding environment.

**Available transports:**
- `stdio` - agent spawns the server as a subprocess (simplest, works everywhere)
- `SSE` - server runs independently, agent connects via HTTP

---

## Step 1: Get your Grafana Cloud credentials

You need a **Service Account token** with appropriate scopes.

1. Go to your Grafana Cloud instance > **Administration > Service Accounts**
2. Create a service account with the `Viewer` role (add `Editor` if you need write operations)
3. Generate a token for that service account
4. Note your Grafana URL (e.g. `https://myorg.grafana.net`) and the token

For Grafana Cloud Prometheus/Loki/Tempo access you may also need:
- **Metrics username** and API key (from Cloud Portal > Stack > Details)
- Or a single Cloud Access Policy token with the required scopes

---

## Step 2: Install the Grafana MCP server

```bash
# Via Go (recommended - always gets latest)
go install github.com/grafana/mcp-grafana/cmd/mcp-grafana@latest

# Verify
mcp-grafana --version
```

Alternatively, download a pre-built binary from the [releases page](https://github.com/grafana/mcp-grafana/releases).

---

## Step 3: Configure Claude Code

Add the server to Claude Code's MCP configuration. The config file is at:
- macOS/Linux: `~/.claude/settings.json` or the project's `.claude/settings.json`

```json
{
  "mcpServers": {
    "grafana": {
      "command": "mcp-grafana",
      "args": [],
      "env": {
        "GRAFANA_URL": "https://myorg.grafana.net",
        "GRAFANA_API_KEY": "glsa_xxxx"
      }
    }
  }
}
```

**Read-only mode** (safer for exploration - disables all write tools):

```json
{
  "mcpServers": {
    "grafana": {
      "command": "mcp-grafana",
      "args": ["--disable-write"],
      "env": {
        "GRAFANA_URL": "https://myorg.grafana.net",
        "GRAFANA_API_KEY": "glsa_xxxx"
      }
    }
  }
}
```

Restart Claude Code after editing settings. Run `/mcp` in Claude Code to verify the server appears and its tools are listed.

---

## Step 4: Configure Cursor

In Cursor: **Settings > Features > MCP Servers** (or edit `~/.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "grafana": {
      "command": "mcp-grafana",
      "args": [],
      "env": {
        "GRAFANA_URL": "https://myorg.grafana.net",
        "GRAFANA_API_KEY": "glsa_xxxx"
      }
    }
  }
}
```

---

## Step 5: Run as SSE server (for team sharing or VS Code)

Run the server as a long-lived SSE process instead of per-session stdio:

```bash
GRAFANA_URL=https://myorg.grafana.net \
GRAFANA_API_KEY=glsa_xxxx \
mcp-grafana --transport sse --port 3001
```

Then point agents at `http://localhost:3001/sse`.

**VS Code MCP extension config (`settings.json`):**

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

---

## Step 6: Available tools and what they do

Once connected, the agent can call:

**Query tools:**
- `query_prometheus` - run PromQL queries against Grafana Cloud Metrics
- `query_loki` - run LogQL queries against Grafana Cloud Logs
- `query_tempo` - run TraceQL queries against Grafana Cloud Traces
- `list_datasources` - enumerate configured data sources

**Dashboard tools:**
- `search_dashboards` - find dashboards by name, tag, or folder
- `get_dashboard` - retrieve full dashboard JSON
- `create_dashboard` - create or update a dashboard (requires Editor role)

**Alerting and incident tools:**
- `list_alert_rules` - list firing and pending alerts
- `get_alert_rule` - get details of a specific alert rule
- `list_incidents` - list active incidents (requires IRM)

**Fleet Management tools (if collector-app is installed):**
- `list_collectors` - list Alloy collectors and their health status
- `list_pipelines` - list remote configuration pipelines
- `get_pipeline` - get pipeline YAML content

**Annotation tools:**
- `list_annotations` - search dashboard annotations by time range
- `create_annotation` - add an annotation to a dashboard

---

## Step 7: Verify the connection

In Claude Code, ask the agent to use a Grafana tool:

```
What data sources are configured in my Grafana instance?
```

Or:

```
Show me dashboards tagged with "kubernetes" in my Grafana.
```

If the tool call fails:
- Check `GRAFANA_URL` has no trailing slash
- Confirm the API key has not expired
- Try `mcp-grafana --debug` to see raw request/response logs

---

## Step 8: Use with the Grafana Skills

If you have the `grafana-core` skills installed, the agent already knows:
- PromQL query patterns (from `grafana-core/promql`)
- Dashboard structure (from `grafana-core/dashboarding`)
- Fleet Management concepts (from `grafana-cloud/fleet-management`)

Combined with the MCP tools, the agent can answer questions like:
- "What is the p95 latency of the payments service over the last hour?"
- "Create a dashboard showing CPU and memory usage for the production cluster"
- "Which collectors are unhealthy and what errors do they have?"
- "Show me all alert rules that fired in the last 24 hours"

---

## Grafana Assistant A2A (Agent-to-Agent)

The Grafana Assistant supports the A2A protocol for agent-to-agent communication. External agents
can discover available Grafana agents at:

```
GET https://<GRAFANA_ASSISTANT_HOST>/.well-known/agent.json
```

This returns an Agent Card describing the supervisor agent's capabilities. Use this for
programmatic integration when building agents that need to delegate observability reasoning
to the Grafana Assistant.

---

## Security considerations

- Store API keys in environment variables or a secrets manager - never in committed files
- Use read-only mode (`--disable-write`) for shared or CI environments
- Scope service account permissions to the minimum required (Viewer is sufficient for queries)
- Rotate tokens periodically via Administration > Service Accounts

---

## References

- [Grafana MCP server (github.com/grafana/mcp-grafana)](https://github.com/grafana/mcp-grafana)
- [Model Context Protocol specification](https://spec.modelcontextprotocol.io/)
- [Grafana Cloud API documentation](https://grafana.com/docs/grafana-cloud/developer-resources/api-reference/)
- [Grafana Assistant documentation](https://grafana.com/docs/grafana-cloud/machine-learning/assistant/)
