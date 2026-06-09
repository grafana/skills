---
name: assistant-mcp
license: Apache-2.0
description: Connect AI coding agents (Claude Code, Cursor, VS Code, OpenAI Codex) to Grafana Cloud via the `mcp-grafana` Model Context Protocol server. Installs the server with `go install`, generates a Grafana service-account token, wires `~/.claude/settings.json` or `~/.cursor/mcp.json` with the `command` + `env` block, runs `--disable-write` for safer read-only sessions, switches to SSE transport for team-shared / VS Code setups, and verifies with `/mcp` + a `list_datasources` round-trip. Use when connecting Claude Code to Grafana, setting up MCP for Grafana, configuring the Grafana MCP server, using Grafana tools in Cursor/VS Code, querying Grafana from an AI agent, sharing the MCP server across a team — even when the user says "give my agent Grafana access", "let Claude see my metrics", or "Cursor + Grafana" without saying "MCP".
---

# Grafana Cloud MCP Server Setup

The Grafana MCP server exposes Grafana Cloud capabilities as tools that AI agents can call via the Model Context Protocol. Agents can then query metrics, search dashboards, manage alerts, investigate incidents, and interact with Fleet Management without leaving the coding environment.

Transports: `stdio` (agent spawns the server as a subprocess, simplest), or `SSE` (server runs independently, agents connect via HTTP — see [references/sse-transport.md](references/sse-transport.md)).

## Common Workflows

### Connecting Claude Code to Grafana (stdio)

```bash
# 1. Install the server
go install github.com/grafana/mcp-grafana/cmd/mcp-grafana@latest

# 2. Verify the binary
mcp-grafana --version
# If "command not found": ensure $GOPATH/bin (or $HOME/go/bin) is on PATH.
```

3. **Get a service-account token**: Grafana Cloud → Administration → Service Accounts → create with `Viewer` role (add `Editor` only if you need writes) → generate token. Note the Grafana URL (e.g. `https://myorg.grafana.net`).

4. **Wire `~/.claude/settings.json`** (or project-local `.claude/settings.json`):

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

   `--disable-write` is the safer default — drop it once you've verified the read path works.

5. **Restart Claude Code, then verify**:

   ```
   /mcp
   ```

   The `grafana` server should appear with its tool list. Then ask:

   ```
   What data sources are configured in my Grafana instance?
   ```

   A clean response = working. If the tool call fails:
   - Check `GRAFANA_URL` has no trailing slash
   - Confirm the API key hasn't expired
   - Re-run with `mcp-grafana --debug` to see raw request/response

### Connecting Cursor

Same Grafana token. Settings → Features → MCP Servers (or edit `~/.cursor/mcp.json`):

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

Verify the same way — Cursor surfaces MCP servers in its agent panel; run a query like "list dashboards tagged kubernetes".

### Sharing the server across a team (SSE)

Switch from `stdio` to `SSE` so the server runs once and many agents connect to it. Full setup with VS Code config in [references/sse-transport.md](references/sse-transport.md).

## Security considerations

- API keys belong in env vars or a secrets manager — never in committed files.
- Use `--disable-write` for shared environments and CI; only lift it on the specific machine where the agent should be allowed to mutate Grafana.
- Scope service-account permissions to the minimum: `Viewer` is enough for queries and dashboard reads. Only grant `Editor` when the agent needs to create dashboards or annotations.
- Rotate tokens periodically via Administration → Service Accounts.

## References

- [`references/tools.md`](references/tools.md) — full list of MCP tools exposed (query / dashboard / alerting / Fleet Management / annotations) and how to discover the live set
- [`references/sse-transport.md`](references/sse-transport.md) — SSE setup for team sharing and VS Code, with stdio-vs-SSE decision matrix + common failure modes
- [`references/a2a.md`](references/a2a.md) — Agent-to-Agent (A2A) protocol for delegating reasoning to the Grafana Assistant (vs direct tool calls via MCP)

## External resources

- [Grafana MCP server (github.com/grafana/mcp-grafana)](https://github.com/grafana/mcp-grafana)
- [Model Context Protocol specification](https://spec.modelcontextprotocol.io/)
- [Grafana Cloud API documentation](https://grafana.com/docs/grafana-cloud/developer-resources/api-reference/)
- [Grafana Assistant documentation](https://grafana.com/docs/grafana-cloud/machine-learning/assistant/)
