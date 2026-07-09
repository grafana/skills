# Project layout (standalone operator mode)

```
my-app/
├── cmd/
│   └── operator/           # Build target — `main` package
├── kinds/                  # CUE kind definitions (source of truth)
│   ├── manifest.cue        # App-level manifest + version declarations
│   ├── mykind.cue          # Kind metadata for MyKind
│   └── mykind_v1alpha1.cue # Version schema for MyKind v1alpha1
├── pkg/
│   ├── generated/          # Generated Go code — DO NOT edit manually
│   ├── watchers/           # Watcher stubs from `project component add operator`
│   └── app/
│       └── app.go          # Entry point — implement `app.App` interface here
├── definitions/            # Generated CRD + manifest files — DO NOT edit manually
├── local/
│   ├── additional/         # Extra YAML manifests for local deployment
│   ├── generated/          # Generated local-deploy manifests (don't commit)
│   ├── mounted-files/      # Mounted into the k3d cluster (don't commit)
│   ├── scripts/            # Generated scripts (don't commit)
│   ├── Tiltfile            # Tiltfile for local stack
│   └── config.yaml         # Local setup config
├── go.mod
└── Makefile
```

## What you edit vs what's generated

| Edit by hand | Regenerate from CUE |
|---|---|
| `kinds/*.cue` | `pkg/generated/**` |
| `pkg/app/app.go`, `pkg/watchers/*.go` | `definitions/*` |
| `cmd/operator/main.go` (rarely) | TypeScript types (frontend) |

Rerun `grafana-app-sdk generate` after every kind change.
