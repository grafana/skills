# Grafana Skills

[![Validate Marketplace](https://github.com/grafana/skills/actions/workflows/validate.yml/badge.svg)](https://github.com/grafana/skills/actions/workflows/validate.yml)
[![Lint Skills](https://github.com/grafana/skills/actions/workflows/lint-skills.yml/badge.svg)](https://github.com/grafana/skills/actions/workflows/lint-skills.yml)

Public skills for working with Grafana, Prometheus, Loki, Tempo, Pyroscope, k6, and the broader LGTM observability
stack. Compatible with Claude Code, Cursor, Codex, and any tool supporting the
[Agent Skills](https://agentskills.io) open standard.

## Installation

### npx skills (recommended for most tools)

Any tool following the [Agent Skills](https://agentskills.io) standard can install directly:

```bash
npx skills add grafana/skills
```

### Claude Code

```bash
# Add this marketplace
claude plugin marketplace add grafana/skills

# Install the plugin(s) you want
claude plugin install grafana-plugins@grafana-skills
claude plugin install grafana-core@grafana-skills
claude plugin install grafana-cloud@grafana-skills
claude plugin install grafana-lgtm@grafana-skills
claude plugin install grafana-app-sdk@grafana-skills
claude plugin install grafana-k6@grafana-skills
```

### Cursor

Install via the `npx skills` command shown above:

```bash
npx skills add grafana/skills
```

This writes skills into `.cursor/skills/` in your project so Cursor's agent can load them.

> Cursor's built-in **Add Rule → Remote Rule (GitHub)** flow is not compatible with this repository. That importer only accepts Cursor Project Rules (`.mdc` files under `.cursor/rules/`), and the Grafana Skills repo follows the [Agent Skills](https://agentskills.io) standard instead (`SKILL.md` files under `skills/`).

### Codex and other Agent Skills tools

Skills are discovered automatically via the `.agents-plugin/marketplace.json` manifest. No manual setup needed — Codex loads matching skills based on your task context.

To install manually into a repo's `.agents/skills/` directory:

```bash
npx skills add grafana/skills
```

---

## Available Skills

Skills are organized into plugin groups. All skill files live under `skills/<plugin-name>/`.

### grafana-core

Core Grafana concepts — dashboards, visualization, PromQL, alerting, and telemetry collection.

| Skill | Description |
|-------|-------------|
| [grafana-oss](skills/grafana-core/grafana-oss) | Grafana OSS core — dashboards, data sources, provisioning, RBAC, and server configuration |
| [dashboarding](skills/grafana-core/dashboarding) | Create and organise Grafana dashboards — panels, variables, transformations, and thresholds |
| [promql](skills/grafana-core/promql) | Write, validate, and optimise PromQL queries for Prometheus and Grafana Cloud Metrics |
| [alerting-irm](skills/grafana-core/alerting-irm) | Grafana Alerting, Incident Response Management, and SLOs — rules, contact points, and on-call |
| [alloy](skills/grafana-core/alloy) | Grafana Alloy OpenTelemetry collector — config language, components, and telemetry pipelines |
| [beyla](skills/grafana-core/beyla) | Grafana Beyla eBPF auto-instrumentation for zero-code application observability |
| [opentelemetry](skills/grafana-core/opentelemetry) | OpenTelemetry with the Grafana stack — SDK instrumentation, OTLP, and collectors |

### grafana-cloud

Grafana Cloud — fleet management, cloud integrations, cost optimization, and AI agent connectivity.

| Skill | Description |
|-------|-------------|
| [admin](skills/grafana-cloud/admin) | Grafana Cloud account management — organizations, stacks, RBAC, SSO, and service accounts |
| [send-data](skills/grafana-cloud/send-data) | Send telemetry to Grafana Cloud — metrics, logs, traces, and profiles via Alloy or SDKs |
| [fleet-management](skills/grafana-cloud/fleet-management) | Manage Grafana Alloy collector fleets with remote configuration and OpAMP |
| [cloud-integrations](skills/grafana-cloud/cloud-integrations) | Connect AWS, Azure, and other cloud providers to Grafana Cloud |
| [infrastructure](skills/grafana-cloud/infrastructure) | Infrastructure monitoring — Kubernetes, host/container metrics, and cloud integrations |
| [app-observability](skills/grafana-cloud/app-observability) | Application Observability (APM), Frontend Observability (Faro), and AI Observability |
| [database-observability](skills/grafana-cloud/database-observability) | Query-level performance insights for MySQL and PostgreSQL |
| [adaptive-metrics](skills/grafana-cloud/adaptive-metrics) | Reduce metrics cost with Adaptive Metrics aggregation rules and cardinality management |
| [cost-management](skills/grafana-cloud/cost-management) | Grafana Cloud cost monitoring, attribution, usage alerts, and optimization |
| [dpm-finder](skills/grafana-cloud/dpm-finder) | Identify Prometheus metrics driving high Data Points per Minute (DPM) |
| [loki-label-analyzer](skills/grafana-cloud/loki-label-analyzer) | Evaluate and improve Loki label strategy using cardinality, query patterns, and label hygiene |
| [prometheus-label-strategy](skills/grafana-cloud/prometheus-label-strategy) | Audit and design Prometheus label schemas — cardinality, histograms, source-side prevention |
| [prometheus-cardinality-troubleshooter](skills/grafana-cloud/prometheus-cardinality-troubleshooter) | Diagnose live Prometheus cardinality issues — slow queries, OOMs, high Active Series bills |
| [oncall-irm](skills/grafana-cloud/oncall-irm) | Grafana OnCall and IRM — alert routing, escalation chains, and incident lifecycle |
| [ml-ai](skills/grafana-cloud/ml-ai) | AI/ML features — Grafana Assistant, Dynamic Alerting, Sift, Knowledge Graph, and LLM Plugin |
| [assistant-mcp](skills/grafana-cloud/assistant-mcp) | Connect AI coding agents (Claude Code, Cursor, Codex) to Grafana Cloud via MCP |
| [private-connectivity](skills/grafana-cloud/private-connectivity) | Private network connectivity — AWS PrivateLink, Azure Private Link, GCP Private Service Connect |
| [testing](skills/grafana-cloud/testing) | Synthetic Monitoring, k6 Cloud load testing, and Frontend Observability |

### grafana-lgtm

Open-source LGTM observability stack — Loki, Tempo, Prometheus/Mimir, and Pyroscope.

| Skill | Description |
|-------|-------------|
| [loki](skills/grafana-lgtm/loki) | Log aggregation with Grafana Loki — LogQL queries, pipelines, and architecture |
| [tempo](skills/grafana-lgtm/tempo) | Distributed tracing with Grafana Tempo — TraceQL, service graphs, and correlations |
| [prometheus](skills/grafana-lgtm/prometheus) | Metrics with Prometheus — PromQL, alerting, recording rules, and Mimir |
| [mimir](skills/grafana-lgtm/mimir) | Scalable long-term metrics storage with Grafana Mimir — architecture and operations |
| [pyroscope](skills/grafana-lgtm/pyroscope) | Continuous profiling with Grafana Pyroscope — flame graphs, diff views, and language support |

### grafana-plugins

Skills for building Grafana plugins — bundle optimisation, code splitting, React 19 migration, and the @grafana/scenes framework.

| Skill | Description |
|-------|-------------|
| [plugin-bundle-size](skills/grafana-plugins/plugin-bundle-size) | Optimise Grafana app plugin bundle size using React.lazy, Suspense, and webpack code splitting |
| [react-19-plugin-migration](skills/grafana-plugins/react-19-plugin-migration) | Migrate a Grafana plugin to React 19 compatibility ahead of Grafana 13 |
| [grafana-scenes](skills/grafana-plugins/grafana-scenes) | Build Grafana plugin pages using the @grafana/scenes framework |

### grafana-app-sdk

Skills for building apps on the Grafana App Platform using grafana-app-sdk.

| Skill | Description |
|-------|-------------|
| [app-sdk-concepts](skills/grafana-app-sdk/app-sdk-concepts) | Project init, deployment modes (standalone operator, grafana/apps, frontend-only), and workflow |
| [cue-kind-definition](skills/grafana-app-sdk/cue-kind-definition) | Author CUE kind definitions — schemas, versioning, spec vs status, codegen config |
| [reconciler-logic](skills/grafana-app-sdk/reconciler-logic) | Implement async reconciler and watcher business logic |
| [admission-control](skills/grafana-app-sdk/admission-control) | Write validation and mutation admission handlers |

### grafana-k6

Skills for working with k6 open-source load testing.

| Skill | Description |
|-------|-------------|
| [k6](skills/grafana-k6/k6) | k6 performance and load testing — test scripts, executors, thresholds, scenarios, and k6 Cloud execution |
| [k6-docs](skills/grafana-k6/k6-docs) | Write or review k6 documentation across TypeScript types, user docs, and release notes |
| [k6-perf-test-website](skills/grafana-k6/k6-perf-test-website) | Performance-test a public website end-to-end with k6. Produces a hybrid protocol+browser test suite, SLO-backed thresholds, a load-generator monitor sidecar, and a Grafana-side investigation playbook |
| [k6-manage](skills/grafana-k6/k6-manage) | Operate Grafana Cloud k6 (GCk6) via the `gcx` CLI or direct curl — manage tests, runs, scripts, schedules, and env vars; fetch logs, metrics, traces, screenshots, and Cloud Insights |

---

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a new skill.

Quick start:

1. Copy `template/SKILL.md` to `skills/<plugin-name>/<skill-name>/SKILL.md`
2. Fill in the frontmatter and content
3. Run `./scripts/lint-skills.sh skills` to validate
4. Open a PR

## Repository Structure

```
grafana-skills/
├── .claude-plugin/marketplace.json   # Claude Code marketplace manifest
├── .cursor-plugin/marketplace.json   # Cursor marketplace manifest (identical)
├── .agents-plugin/marketplace.json   # Codex marketplace manifest (identical)
├── skill-registry.json               # Machine-readable skill manifest
├── skills/                           # All skills, grouped by plugin
│   ├── grafana-core/
│   ├── grafana-cloud/
│   ├── grafana-lgtm/
│   ├── grafana-plugins/
│   ├── grafana-app-sdk/
│   └── grafana-k6/
├── template/SKILL.md                 # Starter template for new skills
├── scripts/lint-skills.sh            # Local skill validation
└── .github/workflows/                # CI validation
```

## License

Apache License 2.0 - see [LICENSE](LICENSE).
