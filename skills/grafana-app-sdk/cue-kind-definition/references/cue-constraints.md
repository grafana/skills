# CUE Constraints Reference

CUE (Configure, Unify, Execute) is a constraint-based language. Values are not assigned — they are constrained. Every field is the intersection (`&`) of all constraints applied to it.

## Basic Types

```cue
myString:  string
myInt:     int
myFloat:   float
myBool:    bool
myBytes:   bytes
myNull:    null
```

## Disjunctions (OR / enums)

```cue
// String enum
status: "pending" | "active" | "archived"

// Type or null (optional)
description: string | null

// Multiple types
value: int | string
```

## Default Values

```cue
// Optional string with default
description: string | *""

// Optional bool with default
enabled: bool | *true

// Optional int with default
replicas: int | *1

// Optional enum with default
priority: "low" | "medium" | "high" | *"medium"
```

## Constraints

Constraints use the `&` (unify/intersect) operator:

```cue
// Numeric bounds
port:    int & >=1 & <=65535
count:   int & >=0
percent: float & >=0 & <=100

// String length
name:    string & strings.MinRunes(1) & strings.MaxRunes(63)

// Regex patterns
slug:    string & =~"^[a-z][a-z0-9-]*$"
email:   string & =~"^[^@]+@[^@]+\\.[^@]+$"
semver:  string & =~"^v?[0-9]+\\.[0-9]+\\.[0-9]+"

// Non-empty string
title:   string & != ""
```

## Lists

```cue
// List of any type
items: [...]

// List of strings (scalars — inline fine)
tags: [...string]

// List of objects — always use a #Definition, never inline the struct
// ❌ Avoid:
// rules: [...{ path: string, method: string }]

// ✅ Preferred:
#Rule: {
    path:   string
    method: "GET" | "POST" | "PUT" | "DELETE"
}
rules: [...#Rule]

// Fixed-size list
pair: [string, int]  // exactly 2 elements: a string and an int
```

## Maps / Structs

```cue
// Map from string to string
labels: {[string]: string}

// Map from string to any
annotations: {[string]: _}

// Nested struct
metadata: {
    name:      string
    namespace: string | *"default"
    labels:    {[string]: string} | *{}
}
```

## Optional Fields

In CUE, all struct fields are required unless marked with `?`:

```cue
// Required
title: string

// Optional (may be absent)
description?: string

// Optional with a specific type
config?: {
    timeout: int | *30
}
```

Note: In grafana-app-sdk kind schemas, the common pattern is to use `string | *""` rather than `?` for optional string fields, as it provides a sensible default that the generated Go struct can hold.

## Additional Types

In CUE, non-primitive types can be imported from the standard library. For exmaple, to create a field of go type `time.Time`:
```cue
import "time"

{
    timeField: string & time.Time
}
```

## CUE Imports for Constraints

```cue
import "strings"

name: string & strings.MinRunes(1) & strings.MaxRunes(253)
```

Available standard packages: `strings`, `math`, `list`, `regexp`, `encoding/json`, `encoding/yaml`

## Named Type Definitions (`#` prefix)

CUE supports named struct definitions using `#TypeName`. Inside a `schema` block, these define sub-types that the code generator emits as named Go structs and TypeScript interfaces.

```cue
schema: {
    #Config: {
        timeout: int & >=1 & <=3600 | *30
        retries: int & >=0 & <=10   | *3
    }

    #Rule: {
        path:   string
        weight: int & >=0 & <=100
    }

    #ResourceRef: {
        name:      string & != ""
        namespace: string | *"default"
    }

    spec: {
        config:    #Config
        rules:     [...#Rule] | *[]
        targetRef: #ResourceRef
    }
}
```

**Scope:** `#` definitions are scoped to the `schema` block they are declared in and cannot be referenced outside it.

**Generated output:** Each `#TypeName` produces a named type in Go and TypeScript:
- Go: `type Config struct { Timeout int \`json:"timeout"\`; Retries int \`json:"retries"\` }`
- TypeScript: `interface Config { timeout: number; retries: number; }`

**Prefer `#` definitions when:**
- The struct is used in more than one field
- The struct is large or complex (many fields, nested constraints)
- The struct appears in a list (`[...#Rule]`) — keeping the list declaration readable

**Inline structs are fine when:**
- The struct is small and simple (2–3 fields)
- It is used in exactly one place and unlikely to be reused

Maps (`{[string]: string}`) and lists of scalars (`[...string]`) are always fine inline.

## Pattern in grafana-app-sdk Kinds

A complete `schema` block with preferred patterns:

```cue
schema: {
    // #Definitions for structs that are large, reused, or appear in lists
    #Config: {
        timeout: int & >=1 & <=3600 | *30
        retries: int & >=0 & <=10   | *3
    }

    #Rule: {
        path:   string
        weight: int & >=0 & <=100
    }

    spec: {
        // Required scalar fields
        title:    string & != ""
        category: "issue" | "feature" | "bug"

        // Optional scalars with defaults
        description: string | *""
        priority:    "low" | "medium" | "high" | *"medium"
        enabled:     bool | *true
        count:       int & >=0 | *0

        // Named definition for a larger/reused struct
        config: #Config

        // Small, simple, single-use struct — inline is fine
        contact: {
            name:  string
            email: string
        }

        // List of scalars (inline fine)
        tags: [...string] | *[]

        // List of objects — prefer a named definition
        rules: [...#Rule] | *[]

        // Map (always inline)
        labels: {[string]: string} | *{}
    }

    // status is written only by the operator/reconciler, never by users.
    status: {
        lastObservedGeneration: int | *0
        state:   string | *""   // e.g. "Ready", "Provisioning", "Error"
        message: string | *""
        // e.g. name of a resource provisioned by the reconciler:
        // provisionedConfigMap: string | *""
    }
}

## Common Mistakes

**Don't use `?` on spec fields that need defaults in Go:**
```cue
// Bad — Go will get zero value, hard to distinguish "not set" from empty
description?: string

// Better — explicit default
description: string | *""
```

**Don't put server state in spec:**
```cue
// Bad — this should be in status
spec: {
    lastUpdated: string  // server writes this
}

// Good
status: {
    lastUpdated: string
}
```

**Do use `!= ""` for required strings:**
```cue
// Bad — accepts empty string
name: string

// Good — rejects empty string at API level
name: string & != ""
```
