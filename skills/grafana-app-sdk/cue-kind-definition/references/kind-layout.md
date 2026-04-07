# Kind Layout Reference

## Overview

The default layout produced by `grafana-app-sdk project kind add` places all CUE files directly in `kinds/`, sharing `package kinds`. A kind is split into two objects:

- **`myKind`** (`myKind.cue`) — common metadata shared across all versions (`kind`, `group`, `scope`, admission config, etc.)
- **`myKindv1alpha1`** (`myKind_v1alpha1.cue`) — per-version schema joined to the metadata via CUE's `&` operator

The app manifest (`myapp.cue`) references version objects directly — no imports needed in the flat layout.

See SKILL.md for the full three-layer anatomy and file structure details.

## Full Example Kind

An example kind with all possible fields populated:
```cue
package kinds

myKind: {
    kind: "MyKind" // [required] The name of the kind
    pluralName: "MyKinds" // [optional] The plural form of `kind`. Defaults to `kind`+`s`
    scope: "Namespaced" // [optional] "Cluster" or "Namespaced", defaults to "Namespaced"
    validation: { // [optional] Validating admission control configuration for the kind
        operations: ["POST","PUT","PATCH"] // values limited to "GET","POST","PUT","DELETE","PATCH"
    }
    mutation: { // [optional] Mutating admission control configuration for the kind
        operations: ["POST","PUT","PATCH"] // values limited to "GET","POST","PUT","DELETE","PATCH"
    }
    conversion: true // [optional] Explicit conversion supported, defaults to false. When true, the App must register a Converter in app.go and ValidateManifest will fail at startup if it is missing.
    conversionWebhookProps: { // [optional] Only required if conversion=true and the app is running as a standalone binary
        url: "https://myapp.svc.cluster.local:443/convert" // The URL of the conversion webhook which should be called to conver the kind between versions
    }
    codegen: {
        ts: { // [optional] TypeScript codegen settings
            enabled: true // [optional] If true TypeScript types are generated for this kind. Defaults to true
            config: { // [optional] Configuration to pass into github.com/grafana/cog when running TypeScript generation
                // [optional] importsMap associates package names to their import path.
                importsMap: {
                    "common": "github.com/example/common"
                }
                // [optional] enumsAsUnionTypes controls how CUE enums (disjunctions) are emitted in TypeScript.
                // false (default): generates a TypeScript enum declaration, e.g.:
                //   enum Direction { Up = "up", Down = "down" }
                // true: generates a union type, e.g.:
                //   type Direction = "up" | "down"
                // Use true when consumers prefer plain string unions over enum objects (e.g. for JSON serialization compatibility).
                enumsAsUnionTypes: false
            }
        }
        go: { // [optional] go codegen settings
            enabled: true // [optional] If true go types are generated for this kind. Defaults to true
        }
    }
}
```
And an example version `v1` of that kind with all possible fields populated:
```cue
package kinds

myKindv1: myKind & {
    // schema is the schema for the kind version, defined as a CUE definition. It must contain at least `spec`. 
    // Any top-level fields aside from `spec` are considered subresources of the object, the most common of which is `status`
    schema: { 
        spec: {
            foo: string
        }
        status: {
            observedGeneration?: int
        }
    }
    // [optional] selectableFields is a list of JSON paths to fields in the schema which can be used as field selectors in the resulting kubernetes API. CRDs limit the number of selectableFields to 8, so it is good practice to have 8 or fewer
    selectableFields: [".spec.foo"]
    // [optional] additionalPrinterColumns is a list of additional columns to display in a `kubectl get` output for the kind
    additionalPrinterColumns: [{
        // name is a human readable name for the column.
        name: "Foo"
        // type is an OpenAPI type definition for this column.
        // See https://github.com/OAI/OpenAPI-Specification/blob/master/versions/2.0.md#data-types for details.
        type: "string"
        // [optional] format is an optional OpenAPI type definition for this column.
        // See https://github.com/OAI/OpenAPI-Specification/blob/master/versions/2.0.md#data-types for details.
        // Use format: "name" on the column that displays the resource name (.metadata.name) — this signals
        // to clients (e.g. kubectl) that the column is the primary identifier.
        format: ""
        // [optional] description is a human readable description of this column.
        description: "Lorem ipsum"
        // priority is an integer defining the relative importance of this column compared to others. Lower
        // numbers are considered higher priority. Columns that may be omitted in limited space scenarios
        // should be given a priority greater than 0.
        priority: 1
        // jsonPath is a simple JSON path (i.e. with array notation) which is evaluated against
        // each custom resource to produce the value for this column.
        jsonPath: ".spec.foo"
    }]
    // [optional] routes is any custom subresource routes for the kind. 
    // Subresource routes differ from subresources defined in `schema` in that they call a handler, rather than 
    // store/retrieve a payload to the underlying storage. Route paths must not conflict with subresources defined in `schema` (like `spec` and `status`)
    routes: {
        // This defines a subresource /message on the kind. Keys in the subsequent map must be all-caps HTTP verbs which correlate to handlers for this subresource
        "message": {
            // This defines a GET handler for the /message subresource
            "GET": {
                name: "getMessage" // name is the OpenAPI name of the route, must begin with a kubernetes verb and match the regex `^(get|log|read|replace|patch|delete|deletecollection|watch|connect|proxy|list|create|patch)([A-Za-z0-9]+)$`
                // [optional] request information
                request: {
                    // query parameters
                    query: {
                        echo: int
                    }
                }
                // successful response schema
                response: {
                    message: string
                }
                // [optional] kubernetes metadata to include in the response payload (impacts codegen and OpenAPI)
                responseMetadata: {
                    typeMeta: true // [optional] include meta/v1.TypeMeta (`kind` and `apiVersion`), defaults to true
                    objectMeta: false // [optional] include a `metadata` field that contains meta/v1.ObjectMeta (defaults to false). Mutually exclusive with `listMeta`
                    listMeta: false // [optional] include a `metadata` field that contains meta/v1.ListMeta (defaults to false). Mutually exclusive with `objectMeta`
                }
                // OpenAPI extensions to add to the generated OpenAPI for the route
                extensions: {
                    "x-myapp-some-extension": "foo"
                }
            }
            // This defines a POST handler for the /message subresource
            "POST": {
                name: "replaceMessage"
                request: {
                    // [optional] request body schema
                    body: {
                        message: string
                    }
                }
                response: {
                    message: string
                }
            }
        }
    }
}
```