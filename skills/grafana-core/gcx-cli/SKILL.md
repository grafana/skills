---
name: gcx-cli
license: Apache-2.0
description: Install, authenticate, and use gcx - the Grafana CLI for Grafana Cloud, Enterprise, and OSS (Grafana 12+). Covers SHA-verified install, `gcx login` (OAuth for Cloud, token for self-hosted), context management, the three-step execution ladder (dedicated command > `gcx api` > curl), command discovery via `gcx help-tree`, agent-mode output, and gcx's bundled agent skills (`gcx agent skills install`). Use when a skill or workflow references a `gcx` command, when you need an authenticated path to Grafana APIs from a terminal or coding agent without pasting tokens, or when installing, updating, logging into, or troubleshooting gcx - even when the user says "call the Grafana API from my terminal", "query my stack from the CLI", or "is there a CLI for Grafana" without naming gcx.
---

# gcx - the Grafana CLI

> **Repo**: https://github.com/grafana/gcx

gcx gives you and your coding agent structured, authenticated access to Grafana: dashboards, alerts, SLOs, metrics, logs, traces, fleet, k6, and more. It works with Grafana Cloud, Enterprise, and OSS (Grafana 12+), and detects when an agent is driving it (Claude Code, Cursor, Copilot) to switch to compact JSON output with stable exit codes.

Other skills in this catalog reference gcx as the preferred execution path in their "Execution paths" sections. This skill is the shared setup and usage reference they point to.

## Install

Quick install (Linux/macOS) - downloads the latest release, verifies the SHA-256 checksum, installs to `~/.local/bin`:

```bash
curl -fsSL https://raw.githubusercontent.com/grafana/gcx/main/scripts/install.sh | sh
```

Homebrew (macOS and Linux):

```bash
brew install grafana/grafana/gcx
```

Pre-built binaries for Linux/macOS/Windows are on the [releases page](https://github.com/grafana/gcx/releases); verify against the `checksums.txt` asset.

Verify the install:

```bash
gcx version
```

## Log in

Contexts are named connections to Grafana instances. One-time per stack:

```bash
# Grafana Cloud - OAuth browser flow
gcx login prod --server https://<your-stack>.grafana.net

# Self-hosted Grafana (OSS / Enterprise, 12+) - service-account token
gcx login local --server http://localhost:3000 --token <token>

# Confirm connectivity
gcx config check          # expect "Connectivity: online"
gcx config list-contexts  # all configured stacks
```

Every subsequent gcx call inherits the active context's auth - never add `Authorization` headers yourself. Switch stacks with `gcx config use-context <name>` or per-call `--context <name>`. If a call returns "Invalid or expired token", re-run `gcx login`.

## The execution ladder

When a task needs to call a Grafana API, prefer paths in this order:

1. **Dedicated command** - `gcx dashboards search`, `gcx metrics query`, `gcx fleet pipelines list`, `gcx slo definitions list`, and so on. Friendlier ergonomics, pagination handled.
2. **`gcx api <path>`** - direct requests against the Grafana HTTP API for endpoints with no dedicated command. Still gcx auth; no pasted tokens.
3. **curl** - when gcx isn't installed (`command -v gcx` fails), fall back to the curl examples that skills keep alongside their gcx paths.

Discover what exists before falling back:

```bash
gcx help-tree            # compact top-level command tree
gcx help-tree metrics    # drill into one area
```

Use `gcx help-tree <area>` for discovery. Don't dump `gcx commands` output into context or into skill files - it's a very large machine-consumption listing that goes stale.

## Output for agents

- `-o json` forces inline JSON output (opts out of the large-response spill-to-file envelope).
- `--json field1,field2` selects fields without jq; `--json list` discovers available fields.
- `--jq '<expr>'` applies a jq transformation server-side of your pipeline.
- gcx prints a one-line `hint:` to stderr on most calls; redirect with `2>/dev/null` when piping stdout into parsers.

## Bundled agent skills

gcx ships its own agent skills for CLI-coupled operational workflows (alert investigation, dashboard GitOps, SLO management, on-call triage, synthetics). They're embedded in the binary and validated in gcx's CI against the live command tree, so they don't go stale:

```bash
gcx agent skills list                 # what's bundled
gcx agent skills install [SKILL]...   # install into ~/.agents/skills
gcx agent skills get setup-gcx        # print a skill without installing
gcx agent skills update               # refresh installed ones after a gcx upgrade
```

For guided first-time setup beyond this page, use gcx's own `setup-gcx` skill. Where a workflow skill exists in the gcx bundle (for example `investigate-alert`, `manage-dashboards`, `oncall-triage`, `slo-manage`), prefer installing it over re-deriving the workflow - this catalog's skills link to them by name instead of duplicating them.

## Security ground rules

- Never use `--insecure-log-http-payload`. It logs raw credentials, tokens, cookies, and OAuth refresh tokens. Debug with `-v`/`-vv`/`-vvv` instead.
- Never use `gcx config view --raw` in shared logs or agent context - it prints sensitive values. The default output redacts them.
- Commands that print credentials on purpose (for example `gcx k6 auth token`) belong inside command substitution (`TOKEN=$(gcx k6 auth token)`), not echoed into logs or chat.

## Resources

- [gcx repository](https://github.com/grafana/gcx)
- [gcx releases](https://github.com/grafana/gcx/releases)
