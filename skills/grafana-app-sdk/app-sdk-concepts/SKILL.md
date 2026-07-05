---
name: app-sdk-concepts
license: Apache-2.0
description: Use when starting any grafana-app-sdk work — scaffolding a Grafana app, initializing a Grafana App Platform app, picking a deployment mode (standalone operator / grafana/apps / frontend-only), wiring app-specific config, or onboarding to the SDK. Covers `grafana-app-sdk` CLI install, `project init` per deployment mode, project layout, the schema-centric workflow (CUE kinds → generated code → reconciler/admission logic), and `SpecificConfig` for env-driven app configuration. Use even if the user just says "make a new app", "Grafana app platform", "kinds and watchers", "operator scaffold", or asks about `apps/` inside the Grafana repo, without naming the SDK explicitly.
---

# Grafana App SDK Concepts

The grafana-app-sdk is a CLI + Go library for building schema-centric apps on the Grafana App Platform. Apps define resources via CUE schemas ("kinds"), generate Go + TypeScript code, and implement business logic via admission control and reconcilers.

## Prerequisites

```bash
go install github.com/grafana/grafana-app-sdk/cmd/grafana-app-sdk@latest
grafana-app-sdk version   # verify
```

## Common Workflows

### Scaffold a standalone operator app

```bash
# 1. Init the project (use the Go module path)
grafana-app-sdk project init github.com/example/my-app

# 2. Add operator scaffolding — ASK THE USER FIRST.
#    They may prefer to write app.App by hand.
grafana-app-sdk project component add operator

# 3. Verify scaffolded layout
ls pkg/app pkg/watchers cmd/operator
# Expected: app.go, watchers/<kind>.go, main.go
```

Common failure: forgetting `go install` updates the binary — verify with `grafana-app-sdk version` before init.

### Scaffold a grafana/apps-style app (inside `grafana/grafana`)

Only available inside the Grafana repo (or fork) — the init command detects `apps/` and `pkg/registry/apps/` at the repo root.

```bash
mkdir -p apps/my-app && cd apps/my-app
grafana-app-sdk project init github.com/grafana/grafana/apps/my-app

# Keep ONLY: kinds/ pkg/ go.mod go.sum — delete everything else.
cp apps/example/Makefile       apps/my-app/Makefile
cp apps/example/kinds/config.cue apps/my-app/kinds/config.cue   # overwrite
go work use ./apps/my-app
```

Then register the app inside Grafana (`pkg/registry/apps/apps.go` + `register.go`). Full walkthrough in [references/deployment-modes.md](references/deployment-modes.md#grafanaapps).

### End-to-end development loop

```
1. project init               → module, Makefile, kinds/
2. project kind add MyKind    → CUE kind scaffold
3. Edit kinds/*.cue           → schemas, validation, versions
4. grafana-app-sdk generate   → Go types, clients, TS types, AppManifest, CRDs
5. Implement logic            → fill in reconciler / admission stubs
6. (optional) project component add frontend
```

Always rerun `generate` after every CUE change — generated code is the API your reconciler sees.

## Deployment modes (one-line table)

| Mode | When to pick | Where it runs |
|------|--------------|---------------|
| Standalone operator | Outside Grafana repo, want your own binary | Kubernetes operator with its own webhook server |
| grafana/apps | Inside `github.com/grafana/grafana` (or fork) | In-process inside Grafana's API server |
| Frontend-only | UI-only app, no Go logic needed | No backend — TS types only |

Full per-mode init, runtime, and wiring detail in [references/deployment-modes.md](references/deployment-modes.md).

## References

- [`references/deployment-modes.md`](references/deployment-modes.md) — per-mode init, runtime semantics, grafana/apps registration walkthrough
- [`references/project-structure.md`](references/project-structure.md) — standalone project layout, what's hand-edited vs generated
- [`references/cli-reference.md`](references/cli-reference.md) — every `grafana-app-sdk` subcommand with flags
- [`references/specific-config.md`](references/specific-config.md) — `app.Config.SpecificConfig` pattern for feature-flag-driven app config
- [`references/local-development.md`](references/local-development.md) — Tilt + k3d local dev loop
- [`references/local-config.md`](references/local-config.md) — `local/config.yaml` reference

## Resources

- [grafana-app-sdk repo](https://github.com/grafana/grafana-app-sdk)
- [App Platform docs](https://grafana.com/docs/grafana/latest/developers/plugins/app-platform/)
