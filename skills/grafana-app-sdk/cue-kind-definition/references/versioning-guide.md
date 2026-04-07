# Kind Versioning Guide

## Overview

grafana-app-sdk kind versioning mirrors Kubernetes API versioning. Each version represents a distinct schema that is independently accessible via the API at `/apis/<group>/<version>/`. Multiple versions of the same kind can be served simultaneously, which enables non-disruptive schema evolution.

## Version Naming Conventions

Follow Kubernetes conventions:

| Stage | Format | Example | Meaning |
|-------|--------|---------|---------|
| Alpha | `v1alpha1`, `v1alpha2` | First experiment | May change without notice |
| Beta | `v1beta1`, `v1beta2` | Maturing | Likely to become stable |
| Stable | `v1`, `v2` | Shipped | Breaking changes require new version |

Start with `v1alpha1` for new kinds. Graduate to `v1beta1` and `v1` as the schema stabilizes.

## Default Layout (flat)

`grafana-app-sdk project kind add` generates files directly in `kinds/`, all sharing `package kinds`:

```
kinds/
├── manifest.cue           # App manifest
├── myKind.cue             # Common metadata (cross-version)
└── myKind_v1alpha1.cue    # v1alpha1 schema + codegen
```

## Multi-Version Layout

When a kind needs a second version, add a new file alongside the existing ones:

```
kinds/
├── manifest.cue
├── myKind.cue
├── myKind_v1alpha1.cue
└── myKind_v1.cue
```

> Users working with complex kinds may choose to organise into per-kind and per-version subdirectories (each with its own CUE package). That layout requires importing version packages in the app manifest. The flat default requires no imports — version objects are referenced directly since all files share `package kinds`.

## What Must Match Across Versions

Fields declared in the common kind metadata object (`myKind.cue`) must be identical in all versions:

```cue
// kinds/myKind.cue — these must match across ALL versions
myKind: {
    kind:   "MyKind"    // identical in all versions
    group:  "my-app.grafana.app"
    // scope, pluralName, etc.
}
```

Per-version `schema.spec` fields can differ freely.

## Backward-Compatible Changes (safe)

These changes can be made to an existing version's schema:

- **Adding an optional field** — existing resources remain valid; new field defaults to its CUE default
- **Widening a constraint** — e.g. changing `int & >=1` to `int & >=0` (more permissive)
- **Adding a new enum value** — e.g. adding `"archived"` to `"pending" | "active"`
- **Loosening a regex** — making a pattern less restrictive

## Breaking Changes (require a new version)

These changes break existing clients and must be introduced via a new version:

- **Removing a field** — existing resources stored with that field become invalid
- **Renaming a field** — clients using the old name stop working
- **Adding a required field** (no default) — existing resources missing the field fail validation
- **Narrowing a constraint** — e.g. making an `int` field require `>= 0` when `< 0` was previously allowed
- **Changing a field's type** — e.g. changing `string` to `int`
- **Removing an enum value** — resources with that value become invalid

## Adding a New Version

### Step 1: Create the new version schema

1. Create the new version CUE file, and copy the previous version as a starting point, ensuring that the type name has changed (e.g. `mykindv1alpha1: mykind & {...}` to `mykindv1beta1: mykind & {...}`).
2. Add the kind to `manifest.versions[<version>]` in the manifest CUE file. If the new version does not exist in `manifest.versions`, create a new object in `manifest.cue` for the version, e.g.
    ```
    v1beta1: {
        kinds: [mykindv1beta1]
    }
    ```
    And add it to `manifest.versions` using the version as the map key.

```bash
# Scaffold the new version
grafana-app-sdk project kind add MyKind --overwrite
# Then manually copy the v1alpha1 schema to v1/ as a starting point
```

### Step 2: Define the new schema

Create `kinds/myKind_v1.cue` (flat default layout), starting from the previous version's schema:

```cue
package kinds

myKindv1: myKind & {
    schema: {
        spec: {
            // All fields from v1alpha1
            title:       string & != ""
            description: string | *""

            // New in v1 — must have a default to not break existing resources
            category: "general" | "advanced" | *"general"

            // Breaking change from v1alpha1 — that's why we created v1
            // In v1alpha1, `config` was a free-form string; in v1 it's a struct
            config?: {
                timeout: int & >=1 | *30
                retries: int & >=0 | *3
            }
        }
    }

    codegen: {
        ts: { enabled: true }
        go: { enabled: true }
    }
}
```

### Step 3: Register the new version in the app manifest

In the flat layout all objects share `package kinds` — reference them directly, no imports needed:

```cue
// kinds/myapp.cue
package kinds

App: {
    versions: {
        "v1alpha1": { schema: myKindv1alpha1 }
        "v1":       { schema: myKindv1 }
    }
}
```

### Step 4: Run generate

```bash
grafana-app-sdk generate
```

Both versions now have generated Go types and clients.

## Deprecation Strategy

When deprecating an old version:

1. Add the new version to the manifest (both versions served simultaneously)
2. Announce deprecation in docs/changelog
3. Migrate existing resources using a conversion webhook or migration job
4. After all resources are migrated, remove the old version from the manifest
5. Run `generate` to remove the old version's generated code

## Storage Version

Only one version is the "storage version" — the canonical form stored in etcd. The Kubernetes API server converts between versions on read/write. The storage version should be the most recent stable version.

In grafana-app-sdk, the storage version is typically configured in the kind's CUE definition or the app manifest. Check the SDK documentation for the current mechanism.

## Conversion

When multiple versions are served, resources stored in the storage version need to be converted to other versions on read. Conversion can be:

- **Automatic** — for purely additive changes where the new fields have defaults; the SDK may handle this automatically
- **Manual** — for structural changes; implement a conversion function in Go

Conversion logic lives outside the generated code and is registered when building the app.
