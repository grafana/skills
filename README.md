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

1. Open **Cursor Settings** - **Rules, Skills, Subagents**
2. Click **+ New** next to **Rules**
3. Select **Add from GitHub**
4. Enter: `https://github.com/grafana/skills`

Skills stay synced with the repository automatically.

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

Core Grafana concepts — dashboards, panels, PromQL, and visualization.

*Coming soon.*

### grafana-cloud

Grafana Cloud — fleet management, cloud integrations, adaptive metrics, and AI agent connectivity.

*Coming soon.*

### grafana-lgtm

Open-source LGTM observability stack — Loki, Tempo, Prometheus/Mimir, and Pyroscope.

| Skill | Description |
|-------|-------------|
| `loki` | Log aggregation with Grafana Loki — LogQL queries, pipelines, and architecture |
| `tempo` | Distributed tracing with Grafana Tempo — TraceQL, service graphs, and correlations |
| `prometheus` | Metrics with Prometheus — PromQL, alerting, recording rules, and Mimir |
| `pyroscope` | Continuous profiling with Grafana Pyroscope — flame graphs, diff views, and language support |

### grafana-plugins

Skills for building Grafana plugins — bundle optimisation, code splitting, React 19 migration, and the @grafana/scenes framework.

| Skill | Description |
|-------|-------------|
| `plugin-bundle-size` | Optimise Grafana app plugin bundle size using React.lazy, Suspense, and webpack code splitting |
| `react-19-plugin-migration` | Migrate a Grafana plugin to React 19 compatibility ahead of Grafana 13 |
| `grafana-scenes` | Build Grafana plugin pages using the @grafana/scenes framework |

### grafana-app-sdk

Skills for building apps on the Grafana App Platform using grafana-app-sdk.

| Skill | Description |
|-------|-------------|
| `app-sdk-concepts` | Project init, deployment modes (standalone operator, grafana/apps, frontend-only), and workflow |
| `cue-kind-definition` | Author CUE kind definitions — schemas, versioning, spec vs status, codegen config |
| `reconciler-logic` | Implement async reconciler and watcher business logic |
| `admission-control` | Write validation and mutation admission handlers |

### grafana-k6

Skills for working with k6 open-source load testing.

| Skill | Description |
|-------|-------------|
| `k6-docs` | Write or review k6 documentation across TypeScript types, user docs, and release notes |

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
