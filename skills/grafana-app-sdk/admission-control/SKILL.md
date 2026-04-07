---
name: admission-control
license: Apache-2.0
description: Use when the user asks to "write a validator", "add validation", "implement admission control", "write a mutating webhook", "add a mutation handler", "validate incoming resources", "implement admission logic", "add admission webhooks", "write ingress validation", or asks how to validate or mutate resources before they are persisted in a grafana-app-sdk app. Provides guidance on implementing validation and mutation admission handlers for grafana-app-sdk apps.
---

# Admission Control

Admission control intercepts resource create/update requests before they are persisted. In grafana-app-sdk there are two types:

- **Validation** — accept or reject a request; cannot modify the resource
- **Mutation** — modify the resource before it is persisted (e.g. set defaults, normalize fields)

The app business logic for admission is identical whether the app runs as a standalone operator or inside `grafana/apps`. The only difference is the runtime: standalone apps stand up their own webhook server; `grafana/apps` apps have admission auto-registered as a Kubernetes plugin.

## Getting Stubs

For standalone apps, if `pkg/app/app.go` does not yet exist, a stub App can be generated with:

```bash
grafana-app-sdk project component add operator
```

This creates scaffolded `simple.App` which admission handlers can be added to for each kind in `ManagedKinds`.

## Validator Interface

```go
// Implement this interface for each kind you want to validate
type Validator interface {
    Validate(ctx context.Context, request *app.AdmissionRequest) error
}
```

- Return `nil` to admit the request
- Return an error to reject it (the error message is returned to the API caller)
- `app.AdmissionRequest` provides access to the incoming object and operation type
- You can use `k8s.NewAdmissionError(err error, statusCode int, reason string)` (from `"github.com/grafana/grafana-app-sdk/k8s"`) to better control the returned error information

### Validator Example

```go
type MyKindValidator struct{}

func (v *MyKindValidator) Validate(ctx context.Context, req *app.AdmissionRequest) error {
    obj, ok := req.Object.(*v1.MyKind)
    if !ok {
        return fmt.Errorf("admission request object was of invalid type %T (expected *v1.MyKind)", req.Object)
    }

    // Validate spec fields
    if obj.Spec.Title == "" {
        return fmt.Errorf("spec.title is required")
    }

    if obj.Spec.Count < 0 {
        return fmt.Errorf("spec.count must be non-negative, got %d", obj.Spec.Count)
    }

    // Distinguish create vs update
    if req.Action == resource.AdmissionActionUpdate && req.OldObject != nil {
        old, ok := req.OldObject.(*v1.MyKind)
        if !ok {
            return fmt.Errorf("admission request old object was of invalid type %T (expected *v1.MyKind)", req.OldObject)
        }
        if old.Spec.Title != obj.Spec.Title {
            return fmt.Errorf("spec.title is immutable after creation")
        }
    }

    return nil
}
```

## Mutating Admission (Mutator)

```go
// Implement this interface to mutate resources before persistence
type Mutator interface {
    Mutate(ctx context.Context, request *app.AdmissionRequest) (*app.MutatingResponse, error)
}
```

- Return a `MutatingResponse` containing the (optionally modified) object
- Return an error to reject the request entirely
- Best practice is to reject requests from validators, not mutators

### Mutating Handler Example

```go
type MyKindMutator struct{}

func (m *MyKindMutator) Mutate(
    ctx context.Context,
    req *app.AdmissionRequest,
) (*app.MutatingResponse, error) {
    obj, ok := req.Object.(*v1.MyKind)
    if !ok {
        return nil, fmt.Errorf("admission request object was of invalid type %T (expected *v1.MyKind)", req.Object)
    }

    // Set defaults on create
    if req.Action == resource.AdmissionActionCreate {
        if obj.Spec.Description == "" {
            obj.Spec.Description = "No description provided"
        }
    }

    return &app.MutatingResponse{UpdatedObject: obj}, nil
}
```

## Registering Admission Handlers

Register validators and mutators when building the app in `pkg/app/app.go`:

```go
func New(cfg app.Config) (app.App, error) {
    cfg.KubeConfig.APIPath = "/apis"
    a, err := simple.NewApp(simple.AppConfig{
        ManagedKinds: []simple.AppManagedKind{
            {
                Kind:      v1.MyKindKind(),
                Validator: &MyKindValidator{},
                Mutator:   &MyKindMutator{},
            },
        },
    })
    if err != nil {
      return nil, fmt.Errorf("error creating app: %w", err)
    }
    if err = a.ValidateManifest(cfg.ManifestData); err != nil {
        return nil, fmt.Errorf("app manifest validation failed: %w", err)
    }
    return a, nil
}
```

Note that mutation and validation must also be enabled in the kind's CUE definition (`mutation.operations` and `validation.operations` fields) — see the `cue-kind-definition` skill for details.

## Admission Request Fields

Key fields available on `app.AdmissionRequest`:

| Field | Type | Description |
|-------|------|-------------|
| `Object` | `resource.Object` | The incoming resource (after decoding) |
| `OldObject` | `resource.Object` | Previous state (only on UPDATE operations) |
| `Action` | `resource.AdmissionAction` | `AdmissionActionCreate`, `AdmissionActionUpdate`, `AdmissionActionDelete`, `AdmissionActionConnect` |
| `UserInfo` | `resource.AdmissionUserInfo` | The user making the request |
| `Kind` | `string` | The `Object` kind |
| `Group` | `string` | The `Object` API Group |
| `Version` | `string` | The `Object` API Version |

## Validation Patterns

Common patterns to implement:

```go
// Immutability check
if req.Action == resource.AdmissionActionUpdate && old.Spec.ImmutableField != obj.Spec.ImmutableField {
    return fmt.Errorf("spec.immutableField cannot be changed after creation")
}

// Cross-field validation
if obj.Spec.StartTime.After(obj.Spec.EndTime) {
    return fmt.Errorf("spec.startTime must be before spec.endTime")
}

// Referential validation (e.g. check referenced resource exists)
if _, err := v.client.Get(ctx, resource.Identifier{Name: obj.Spec.RefName, Namespace: obj.Namespace}); err != nil {
    return fmt.Errorf("referenced resource %q not found", obj.Spec.RefName)
}
```

## Deployment Difference

| Mode | Admission runtime |
|------|------------------|
| Standalone operator | App starts a webhook server; Kubernetes routes admission requests to it |
| `grafana/apps` | Admission handlers are auto-registered as a Kubernetes in-process plugin — no separate server required |

The handler code itself is identical in both cases.

## Resources

- [grafana-app-sdk GitHub](https://github.com/grafana/grafana-app-sdk)
- [app package docs](https://pkg.go.dev/github.com/grafana/grafana-app-sdk/app)
