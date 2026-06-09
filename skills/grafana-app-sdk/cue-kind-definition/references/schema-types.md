# Schema field types + named definitions

## Contents

- [Schema field types and constraints](#schema-field-types-and-constraints)
- [Type definitions with `#`](#type-definitions-with-)

## Schema field types and constraints

CUE is a superset of JSON. Commonly used types and constraints:

```cue
// Basic types
myString: string
myInt:    int
myFloat:  float
myBool:   bool
myBytes:  bytes

// Optional with default (using disjunction + *)
name: string | *"default-value"

// Constraints (using & to intersect)
port:  int & >=1 & <=65535
label: string & =~"^[a-z][a-z0-9-]*$"  // regex

// Enums (disjunctions)
status: "pending" | "active" | "archived"

// Maps (always fine inline)
labels: {[string]: string}
attrs:  {[string]: _}

// Lists of scalars (fine inline)
tags: [...string]

// Optional field (no value required)
description?: string
```

## Type definitions with `#`

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
        thresholds:     [...#Threshold]   // list of a defined type
        targetRef?:     #ResourceRef      // optional
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

Maps and lists of scalars are always fine inline.
