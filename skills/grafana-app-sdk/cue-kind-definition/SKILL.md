---
name: cue-kind-definition
license: Apache-2.0
description: Use when working with CUE kind definitions, schemas, or versioning in grafana-app-sdk projects (app platform apps). This skill should be used when the user asks to "define a kind", "add a CUE kind", "write a kind schema", "create a CUE schema", "model a resource", "add a new resource type", "edit kinds/", "what is a kind in grafana-app-sdk", "add a version to a kind", or asks about CUE kind structure, versioning, schema fields, validation constraints, or the codegen configuration section. Provides guidance on authoring CUE kind definitions for grafana-app-sdk projects.
---

# CUE Kind Definition

Kinds are the schema definitions that drive the entire grafana-app-sdk code generation pipeline. Each kind describes a Kubernetes-style resource type: its name, versions, and per-version schema. All Go types, TypeScript types, API clients, CRD manifests, and the AppManifest are generated from these CUE files.

## Adding a Kind

Use the CLI to scaffold a kind before editing:

```bash
grafana-app-sdk project kind add <KindName> --overwrite
```

This creates a `.cue` file with scaffolding, field comments, and example values. Read the generated comments carefully — they explain every field's purpose.

> Always use `--overwrite` when re-running to regenerate scaffolding without losing manual additions.

## Kind File Structure

`grafana-app-sdk project kind add` creates files directly in `kinds/` — the default layout is flat, all in `package kinds`:

```
kinds/
├── manifest.cue           # App manifest + version list declarations
├── mykind.cue             # Common (cross-version) kind metadata
└── mykind_v1alpha1.cue    # v1alpha1 schema + codegen config
```

For multi-version kinds the additional version files sit alongside:

```
kinds/
├── manifest.cue
├── mykind.cue
├── mykind_v1alpha1.cue
└── mykind_v1.cue
```

> For larger, more complex kind definitions users may choose to organise kinds into per-kind and per-version subdirectories, each with their own package. The default CLI output uses the flat layout above.

## CUE Kind Anatomy

A complete kind definition has three layers:

### 1. Common kind metadata (shared across versions)

```cue
// kinds/mykind.cue
package kinds

myKind: {
    kind: "MyKind"               // Required: the kind name (PascalCase)
    // other cross-version fields (scope, pluralName, validation, mutation, conversion, etc.)
    // See references/kind-layout.md for the full field reference
}
```

### 2. Per-version schema (one file per version)

Each version joins the common metadata with its own schema via CUE's `&` operator:

```cue
// kinds/mykind_v1alpha1.cue
package kinds

myKindv1alpha1: myKind & {
    // Version-specific schema
    schema: {
        // spec: desired state — set by users/clients, never by the operator
        spec: {
            title:       string
            description: string | *""     // optional with default
            count:       int & >=0
            enabled:     bool | *true
        }
        // status: observed state — written only by the operator/reconciler,
        // never by users. Mirrors Kubernetes spec/status conventions.
        status: {
            lastObservedGeneration: int | *0
            state:                  string | *""
            message:                string | *""
        }
    }

    // Code generation config
    codegen: {
        ts: { enabled: true }   // generate TypeScript types
        go: { enabled: true }   // generate Go types and client
    }
}
```

### 3. App manifest (version registration)

Since all files share `package kinds`, version objects are referenced directly — no imports needed in the flat layout:

```cue
// kinds/manifest.cue
package kinds

App: {
    appName: "my-app"
    versions: {
        "v1alpha1": {
            schema: myKindv1alpha1
        }
    }
}
```

## spec vs status

This distinction follows Kubernetes conventions exactly:

**`spec`** — desired state. Written by users and clients. The operator reads `spec` and works to make the world match it. Admission handlers validate and mutate `spec`. Never write to `spec` from a reconciler.

**`status`** — observed state. Written only by the operator/reconciler after it has done work. Users and clients should treat `status` as read-only. Admission handlers must not modify `status`.

Typical `status` fields:

```cue
status: {
    // Generation of the spec that was last successfully reconciled.
    // Set to metadata.generation after a successful reconcile loop.
    lastObservedGeneration: int | *0

    // Human-readable summary of current state
    state:   string | *""   // e.g. "Ready", "Provisioning", "Error"
    message: string | *""   // detail, especially on error

    // References to objects created by the reconciler.
    // e.g. the name of a ConfigMap or Deployment the reconciler provisioned.
    provisionedConfigMap: string | *""
    provisionedServiceAccount: string | *""
}
```

Fields that belong in `status`, not `spec`:
- Anything the operator computes or creates (IDs, names, URLs of provisioned resources)
- `lastObservedGeneration` / `observedGeneration`
- `conditions` (Kubernetes-style condition arrays)
- Current health or lifecycle state (`"Ready"`, `"Degraded"`, etc.)
- Timestamps of when the operator last acted

Fields that belong in `spec`, not `status`:
- Everything the user configures as desired state
- References to *existing* resources the user wants the app to interact with (the operator looks these up, it doesn't create them)

## Type Definitions with `#`

CUE supports named type definitions using the `#` prefix inside a `schema` block. Each `#Definition` generates a named Go struct and TypeScript interface alongside the kind's `Spec` type.

```cue
schema: {
    #Threshold: {
        value:    float & >=0
        severity: "info" | "warning" | "critical"
        message:  string | *""
    }

    #ResourceRef: {
        name:      string & != ""
        namespace: string | *"default"
    }

    spec: {
        title:          string & != ""
        alertThreshold: #Threshold
        thresholds:     [...#Threshold]  // list of a defined type
        targetRef?:     #ResourceRef     // optional
    }
}
```

`#` definitions are scoped to the `schema` block they are declared in.

**Prefer `#` definitions when:**
- A struct is used in more than one field
- A struct is large or complex enough that inlining hurts readability
- A struct appears in a list (`[...#MyType]`)

**Inline structs are fine when:**
- The struct is small and simple (2-3 fields) or shallow
- It is used in only one place and unlikely to be reused

Maps (`{[string]: string}`) and lists of scalars (`[...string]`) are always fine inline.

## Schema Field Types

CUE is a superset of JSON. Commonly used types and constraints:

```cue
// Basic types
myString:  string
myInt:     int
myFloat:   float
myBool:    bool
myBytes:   bytes

// Optional with default
name: string | *"default-value"

// Constraints (using & to intersect)
port:     int & >=1 & <=65535
label:    string & =~"^[a-z][a-z0-9-]*$"  // regex constraint

// Enums (disjunctions)
status:   "pending" | "active" | "archived"

// Maps (always fine inline)
labels: {[string]: string}
attrs:  {[string]: _}

// Lists of scalars (fine inline)
tags: [...string]

// Optional field
description?: string
```

## Custom Routes in CUE

Routes can be defined at two levels. Both require corresponding Go handlers registered in `app.go`.

### Kind-level routes

```cue
MyKind: {
    kind: "MyKind"
    schema: { ... }

    routes: {
        "/actions/process": {
            "POST": {
                name: "processMyKind"  // unique within version; must start with a k8s verb
                request: {
                    body: {
                        reason: string
                    }
                }
                response: {
                    jobId:  string
                    status: string
                }
            }
        }
    }
}
```

### Version-level routes

```cue
versions: {
    "v1alpha1": {
        routes: {
            namespaced: {
                "/summary": {
                    "GET": {
                        name: "getNamespacedSummary"
                        response: { count: int }
                    }
                }
            }
            cluster: {
                "/health": {
                    "GET": {
                        name: "getHealth"
                        response: { status: string }
                    }
                }
            }
        }
    }
}
```

After adding routes, run `grafana-app-sdk generate` — routes are included in the AppManifest and `ValidateManifest` will fail if a handler is missing.

## Version Compatibility Rules

When a kind has multiple versions, **fields declared in the common metadata object must match across all versions**. Schema fields (inside `schema.spec`) can differ per version, but:

- The `kind` field must be identical in every version
- Breaking changes (removing fields, changing types, adding required fields) must be introduced via a new version — never by modifying a stable version (`v1`, `v2`)
- Use `status` for server-managed fields; never put mutable server state in `spec`

## Codegen Configuration

Control what gets generated per kind per version:

```cue
codegen: {
    ts: { enabled: true | false }   // TypeScript types
    go: { enabled: true | false }   // Go types + client
}
```

Disabling `go` for frontend-only apps avoids generating unused Go code. Disabling `ts` for backend-only resources reduces TypeScript bundle size. Both default to `true` when omitted.

## After Editing Kinds

Always run generate after any change to `.cue` files:

```bash
grafana-app-sdk generate
```

The generated files in `pkg/generated/` must never be edited manually — they are overwritten on every generate run.

## Resources

- [grafana-app-sdk GitHub](https://github.com/grafana/grafana-app-sdk)
- [CUE Language Reference](https://cuelang.org/docs/)
- [Example kinds layout](https://github.com/grafana/grafana/tree/main/apps/example/kinds)
