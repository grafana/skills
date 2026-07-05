# Available MCP tools

Tools exposed by the Grafana MCP server once connected. The agent calls these by name; this reference is what's available.

## Contents

- [Query tools](#query-tools)
- [Dashboard tools](#dashboard-tools)
- [Alerting + incident tools](#alerting--incident-tools)
- [Fleet Management tools](#fleet-management-tools)
- [Annotation tools](#annotation-tools)

## Query tools

- `query_prometheus` — run PromQL queries against Grafana Cloud Metrics
- `query_loki` — run LogQL queries against Grafana Cloud Logs
- `query_tempo` — run TraceQL queries against Grafana Cloud Traces
- `list_datasources` — enumerate configured data sources

## Dashboard tools

- `search_dashboards` — find dashboards by name, tag, or folder
- `get_dashboard` — retrieve full dashboard JSON
- `create_dashboard` — create or update a dashboard (requires Editor role + writes not disabled)

## Alerting + incident tools

- `list_alert_rules` — list firing and pending alerts
- `get_alert_rule` — details for a specific alert rule
- `list_incidents` — list active incidents (requires IRM)

## Fleet Management tools

Available if `grafana-collector-app` is installed:

- `list_collectors` — list Alloy collectors and their health
- `list_pipelines` — list remote configuration pipelines
- `get_pipeline` — fetch pipeline YAML

## Annotation tools

- `list_annotations` — search dashboard annotations by time range
- `create_annotation` — add an annotation to a dashboard

## How the agent discovers tools

Once connected, run `/mcp` in Claude Code (or the equivalent in Cursor / VS Code) to see the live list. The list above is the canonical set as of the current `mcp-grafana` release; new tools are added in releases, see [github.com/grafana/mcp-grafana releases](https://github.com/grafana/mcp-grafana/releases).
