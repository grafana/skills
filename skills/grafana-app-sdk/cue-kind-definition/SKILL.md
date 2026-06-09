---
name: cue-kind-definition
license: Apache-2.0
description: Author CUE kind definitions for grafana-app-sdk apps - schemas, versioning, field constraints, named type definitions, custom routes, and codegen configuration. Scaffolds kinds via `grafana-app-sdk project kind add`, writes spec/status schemas with type constraints (regex, enum, range), defines `#`-prefixed named types for reusable structs, registers versions in the app manifest, and runs `grafana-app-sdk generate` with explicit error recovery. Use when working with CUE kinds, adding a new resource type, adding a version to an existing kind, writing schema field constraints, defining `#Definition` types, adding custom routes, editing files under `kinds/`, or when the user asks to "model a resource", "add a CUE schema", or "write a kind" — even without saying "CUE" explicitly.
---

# CUE Kind Definition

## Common Workflows

### Adding a new kind

```bash
# 1. Scaffold the kind files
grafana-app-sdk project kind add MyKind --overwrite
# Produces kinds/mykind.cue + kinds/mykind_v1alpha1.cue + updates kinds/manifest.cue.

# 2. Edit the generated .cue files — fill in schema.spec / schema.status fields

# 3. Generate types and clients
grafana-app-sdk generate

# 4. Verify the generated artifacts exist
ls pkg/generated/    # should contain new types for MyKind
```

If `generate` fails with CUE errors:
- Read the error — CUE prints the offending file + line + which constraint failed
- Common causes: missing required field, type mismatch (e.g. `string` field assigned an `int`), unresolved reference between version files
- Fix the `.cue` source, re-run `grafana-app-sdk generate`. Never edit files under `pkg/generated/` — they're overwritten on every run.

### Adding a new version to an existing kind

```bash
# 1. Copy the existing version file
cp kinds/mykind_v1alpha1.cue kinds/mykind_v1.cue

# 2. Edit kinds/mykind_v1.cue — rename the top-level object (e.g. myKindv1) and adjust the schema

# 3. Register the new version in kinds/manifest.cue
#    Add a versions["v1"]: { schema: myKindv1 } entry

# 4. Re-generate
grafana-app-sdk generate

# 5. Verify both versions were generated — per-version Go types live under pkg/generated/<group>/<version>/
ls pkg/generated/             # should list both version directories (e.g. v1alpha1/ v1/)
# Optionally inspect the CRD spec under definitions/ to confirm both versions appear in `spec.versions[]`
```

**Breaking changes** (removing fields, changing types, adding required fields) must go into a new version — never modify a stable version (`v1`, `v2`) in place.

## Kind file structure

The CLI produces a flat layout under `kinds/`:

```
kinds/
├── manifest.cue           # App manifest + version list declarations
├── mykind.cue             # Common (cross-version) kind metadata
└── mykind_v1alpha1.cue    # v1alpha1 schema + codegen config
```

For multi-version kinds, additional version files sit alongside (`mykind_v1.cue`, etc.). For very large kind sets (10+ kinds), consider the per-kind subdirectory layout — full kind anatomy reference in [references/kind-layout.md](references/kind-layout.md).

## CUE Kind Anatomy

Three layers per kind:

### 1. Common kind metadata

```cue
// kinds/mykind.cue
package kinds

myKind: {
    kind: "MyKind"               // Required: PascalCase kind name
    // other cross-version fields (scope, pluralName, validation, mutation, conversion, …)
    // Full field reference in references/kind-layout.md.
}
```

### 2. Per-version schema

```cue
// kinds/mykind_v1alpha1.cue
package kinds

myKindv1alpha1: myKind & {
    schema: {
        spec: {                       // desired state — user-set
            title:       string
            description: string | *""
            count:       int & >=0
            enabled:     bool | *true
        }
        status: {                     // observed state — operator-set
            lastObservedGeneration: int | *0
            state:                  string | *""
            message:                string | *""
        }
    }
    codegen: {
        ts: { enabled: true }
        go: { enabled: true }
    }
}
```

### 3. App manifest

```cue
// kinds/manifest.cue
package kinds

App: {
    appName: "my-app"
    versions: {
        "v1alpha1": { schema: myKindv1alpha1 }
    }
}
```

## Codegen configuration

Control what gets generated per kind per version:

```cue
codegen: {
    ts: { enabled: true | false }   // TypeScript types
    go: { enabled: true | false }   // Go types + client
}
```

Disabling `go` for frontend-only apps avoids unused Go code. Disabling `ts` for backend-only resources reduces bundle size. Both default to `true` when omitted.

## References

- [`references/kind-layout.md`](references/kind-layout.md) — full common-metadata field reference + app manifest fields + per-kind subdirectory layout
- [`references/schema-types.md`](references/schema-types.md) — CUE schema field types (basic types, constraints, regex, enums, maps, lists) + `#`-prefixed named type definitions
- [`references/custom-routes.md`](references/custom-routes.md) — kind-level + version-level custom routes + handler registration in `app.go`

## External resources

- [grafana-app-sdk GitHub](https://github.com/grafana/grafana-app-sdk)
- [CUE Language Reference](https://cuelang.org/docs/)
- [Example kinds layout](https://github.com/grafana/grafana/tree/main/apps/example/kinds)
