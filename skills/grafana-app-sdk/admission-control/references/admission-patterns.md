# Admission Control Patterns

## Error Message Conventions

Return clear, user-actionable error messages. Follow Kubernetes API conventions:

```go
// Field path in dot notation
return fmt.Errorf("spec.title: required field cannot be empty")
return fmt.Errorf("spec.count: must be >= 0, got %d", obj.Spec.Count)
return fmt.Errorf("spec.startTime: must be before spec.endTime")

// For multi-error validation, use a field.ErrorList (if using k8s apimachinery)
// import "k8s.io/apimachinery/pkg/util/validation/field"
var errs field.ErrorList
if obj.Spec.Title == "" {
    errs = append(errs, field.Required(field.NewPath("spec", "title"), ""))
}
if obj.Spec.Count < 0 {
    errs = append(errs, field.Invalid(
        field.NewPath("spec", "count"), obj.Spec.Count, "must be non-negative"))
}
if len(errs) > 0 {
    return errs.ToAggregate()
}
```

Prefer usage of `k8s.NewAdmissionError` when you want to be able to set both the `Message` and `Reason` in the returned `meta.v1.Status` error. Note that `Message` is intended for humans and `Reason` should be a machine-readable description.

## Operation-Specific Validation

```go
func (v *MyKindValidator) Validate(ctx context.Context, req *app.AdmissionRequest) error {
    obj, ok := req.Object.(*v1.MyKind)
    if !ok {
        return fmt.Errorf("admission request object was of invalid type %T (expected *v1.MyKind)", req.Object)
    }
    switch req.Action {
    case resource.AdmissionActionCreate:
        return v.validateCreate(ctx, obj)
    case resource.AdmissionActionUpdate:
        if req.OldObject == nil {
            return errors.New("old object not present in AdmissionRequest")
        }
        old, ok := req.OldObject.(*v1.MyKind)
        if !ok {
            return fmt.Errorf("admission request old object was of invalid type %T (expected *v1.MyKind)", req.OldObject)
        }
        return v.validateUpdate(ctx, old, obj)
    case resource.AdmissionActionDelete:
        return v.validateDelete(ctx, obj)
    }
    return nil
}

func (v *MyKindValidator) validateCreate(ctx context.Context, obj *v1.MyKind) error {
    if obj.Spec.Title == "" {
        return fmt.Errorf("spec.title: required")
    }
    return nil
}

func (v *MyKindValidator) validateUpdate(ctx context.Context, old, updated *v1.MyKind) error {
    // Immutability checks
    if old.Spec.ImmutableField != updated.Spec.ImmutableField {
        return fmt.Errorf("spec.immutableField: field is immutable after creation")
    }
    // General field validation
    return v.validateCreate(ctx, updated)
}

func (v *MyKindValidator) validateDelete(ctx context.Context, obj *v1.MyKind) error {
    if obj.Spec.Permanent {
        return fmt.Errorf("cannot delete objects with spec.permanent set to true")
    }
    return nil
}
```

## Immutability Pattern

For fields that should not change after creation:

```go
func validateImmutableFields(old, new *v1.MyKind) error {
    if old.Spec.TenantID != new.Spec.TenantID {
        return fmt.Errorf("spec.tenantId: immutable after creation")
    }
    if old.Spec.Region != new.Spec.Region {
        return fmt.Errorf("spec.region: immutable after creation")
    }
    return nil
}
```

## Cross-Field Validation

```go
func validateCrossFields(obj *v1.MyKind) error {
    // Time range validation
    if !obj.Spec.StartTime.IsZero() && !obj.Spec.EndTime.IsZero() {
        if !obj.Spec.StartTime.Before(obj.Spec.EndTime) {
            return fmt.Errorf("spec.startTime must be before spec.endTime")
        }
    }

    // Dependency validation
    if obj.Spec.EnableFeatureX && obj.Spec.FeatureXConfig == nil {
        return fmt.Errorf("spec.featureXConfig: required when spec.enableFeatureX is true")
    }

    // Mutual exclusivity
    if obj.Spec.ModeA && obj.Spec.ModeB {
        return fmt.Errorf("spec.modeA and spec.modeB are mutually exclusive")
    }
    return nil
}
```

## Referential Validation

Check that referenced resources actually exist:

```go
import (
    "context"
    "fmt"
    "<module>/pkg/generated/<group>/v1"
    "github.com/grafana/grafana-app-sdk/app"
    "github.com/grafana/grafana-app-sdk/resource"
    apierrors "k8s.io/apimachinery/pkg/api/errors"
)

type MyKindValidator struct {
    otherClient resource.Client
}

// Construct the validator in pkg/app/app.go, injecting a client:
//
//   registry := k8s.NewClientRegistry(cfg.KubeConfig, k8s.DefaultClientConfig())
//   otherClient, err := registry.ClientFor(otherv1.OtherKindKind())
//   validator := &MyKindValidator{otherClient: otherClient}
//
// Alternatively use a generated typed client from the target app if available.

func (v *MyKindValidator) Validate(ctx context.Context, req *app.AdmissionRequest) error {
    obj, ok := req.Object.(*v1.MyKind)
    if !ok {
        return fmt.Errorf("admission request object was of invalid type %T (expected *v1.MyKind)", req.Object)
    }

    if obj.Spec.OtherRef != "" {
        _, err := v.otherClient.Get(ctx, resource.Identifier{
            Name:      obj.Spec.OtherRef,
            Namespace: obj.Namespace,
        })
        if err != nil {
            if apierrors.IsNotFound(err) {
                return fmt.Errorf("spec.otherRef: referenced resource %q not found", obj.Spec.OtherRef)
            }
            return fmt.Errorf("spec.otherRef: validating reference: %w", err)
        }
    }
    return nil
}
```

## Mutation Patterns

### Setting Defaults

```go
func (m *MyKindMutator) Mutate(
    ctx context.Context,
    req *app.AdmissionRequest,
) (*app.MutatingResponse, error) {
    obj, ok := req.Object.(*v1.MyKind)
    if !ok {
        return nil, fmt.Errorf("admission request object was of invalid type %T (expected *v1.MyKind)", req.Object)
    }

    if req.Action == resource.AdmissionActionCreate {
        // Set defaults not expressible in CUE
        if obj.Spec.Description == "" {
            obj.Spec.Description = fmt.Sprintf("Auto-created %s", obj.Name)
        }
        // Copy spec to label for list filtering
        if obj.Spec.UseFor != "" {
            labels := obj.Labels
            if labels == nil {
                labels = make(map[string]string)
            }
            labels["usefor"] = obj.Spec.UseFor
            obj.Labels = labels
        }
    }

    return &app.MutatingResponse{UpdatedObject: obj}, nil
}
```

### Normalizing Input

```go
// Normalize on both create and update
obj.Spec.Title = strings.TrimSpace(obj.Spec.Title)
obj.Spec.Tags = deduplicateAndSort(obj.Spec.Tags)
```

## Testing Admission Handlers

Unit test validators directly without a running server:

```go
func TestMyKindValidator_Validate(t *testing.T) {
    v := &MyKindValidator{}
    ctx := context.Background()

    tests := []struct {
        name    string
        obj     *v1.MyKind
        action  resource.AdmissionAction
        wantErr bool
        errMsg  string
    }{
        {
            name:   "valid create",
            obj:    &v1.MyKind{Spec: v1.MyKindSpec{Title: "Test"}},
            action: resource.AdmissionActionCreate,
        },
        {
            name:    "missing title",
            obj:     &v1.MyKind{Spec: v1.MyKindSpec{}},
            action:  resource.AdmissionActionCreate,
            wantErr: true,
            errMsg:  "spec.title",
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            err := v.Validate(ctx, &app.AdmissionRequest{
                Object: tt.obj,
                Action: tt.action,
            })
            if (err != nil) != tt.wantErr {
                t.Errorf("Validate() error = %v, wantErr %v", err, tt.wantErr)
            }
            if err != nil && tt.errMsg != "" && !strings.Contains(err.Error(), tt.errMsg) {
                t.Errorf("error %q does not contain %q", err.Error(), tt.errMsg)
            }
        })
    }
}
```

## Deployment: Standalone vs grafana/apps

The handler code is identical. The only difference is how admission is registered at runtime:

- **Standalone**: App binary starts an HTTPS webhook server. Kubernetes `ValidatingWebhookConfiguration` and `MutatingWebhookConfiguration` resources route requests to it. The SDK handles this automatically when `component add operator` scaffolding is used.
- **grafana/apps**: Admission handlers are registered in-process via the Grafana API server plugin mechanism. No separate webhook server is needed.
