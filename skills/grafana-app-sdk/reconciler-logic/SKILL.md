---
name: reconciler-logic
license: Apache-2.0
description: Implement reconcilers and watchers for grafana-app-sdk apps — write `TypedReconciler[*MyKind]` reconcile functions, apply generation-based skip patterns, do conflict-safe status updates via `resource.UpdateObject`, configure `BasicReconcileOptions` (namespace, label/field filters, finalizer management), use `Watcher` for event-style handling, reconcile `UnmanagedKinds` (resources your app doesn't own), and register the whole thing in `app.go`. Use when writing a reconciler, implementing the reconcile loop, adding async business logic, handling create/update/delete events, processing resource state changes, scheduling periodic resyncs with `RequeueAfter`, picking between Watcher and Reconciler, or wiring a controller into `app.go` — even when the user says "process this resource", "handle X events", or "write a controller" without saying "reconciler".
---

# Reconciler Logic

Reconcilers are the async business-logic layer of a grafana-app-sdk app. The SDK enqueues a reconcile event when a resource is created, updated, or deleted; the reconciler observes the current state and drives the system toward the desired state.

## Common Workflows

### Implementing a new reconciler end-to-end

```bash
# 1. Generate operator stubs for a standalone app
grafana-app-sdk project component add operator

# 2. Implement the ReconcileFunc — see § TypedReconciler below for the pattern

# 3. Register the reconciler in app.go (see references/registration.md)

# 4. Generate, build, and verify it runs
grafana-app-sdk generate
go build ./...
go run ./cmd/operator   # tail logs — reconcile entries should appear when you kubectl-apply a resource
```

If the operator starts but no reconcile events fire when you create a resource:
- Check `BasicReconcileOptions.Namespace` matches the resource's namespace
- Check `BasicReconcileOptions.LabelFilters` / `FieldSelectors` — most "no events" issues are filter mismatches (`kubectl get <resource> -o yaml` to see labels)
- Confirm the reconciler was attached to the right (latest) version of the kind

## TypedReconciler — preferred pattern

`operator.TypedReconciler` handles type assertion and provides a strongly-typed `ReconcileFunc`:

```go
type MyKindReconciler struct {
    operator.TypedReconciler[*v1alpha1.MyKind]
    client resource.Client
}

func NewMyKindReconciler(client resource.Client) *MyKindReconciler {
    r := &MyKindReconciler{client: client}
    r.ReconcileFunc = r.reconcile  // wire the typed func
    return r
}

func (r *MyKindReconciler) reconcile(
    ctx context.Context,
    req operator.TypedReconcileRequest[*v1alpha1.MyKind],
) (operator.ReconcileResult, error) {
    obj := req.Object

    // Skip if already reconciled this generation
    if obj.GetGeneration() == obj.Status.LastObservedGeneration &&
       req.Action != operator.ReconcileActionDeleted {
        return operator.ReconcileResult{}, nil
    }

    log := logging.FromContext(ctx).With("name", obj.GetName(), "namespace", obj.GetNamespace())
    log.Info("reconciling", "action", operator.ResourceActionFromReconcileAction(req.Action))

    if req.Action == operator.ReconcileActionDeleted {
        return operator.ReconcileResult{}, nil
    }

    // ... business logic ...

    // Atomic status update — see § Status updates below
    _, err := resource.UpdateObject(ctx, r.client, obj.GetStaticMetadata().Identifier(),
        func(obj *v1alpha1.MyKind, _ bool) (*v1alpha1.MyKind, error) {
            obj.Status.LastObservedGeneration = obj.GetGeneration()
            obj.Status.State = "Ready"
            return obj, nil
        },
        resource.UpdateOptions{Subresource: "status"},
    )
    return operator.ReconcileResult{}, err
}
```

`ReconcileAction` values: `ReconcileActionCreated`, `ReconcileActionUpdated`, `ReconcileActionDeleted`, `ReconcileActionResynced`.

To requeue after a delay (e.g. polling an external system):

```go
return operator.ReconcileResult{RequeueAfter: 10 * time.Second}, nil
```

## Status updates with `resource.UpdateObject`

Always use `resource.UpdateObject` for status writes — it fetches the latest version before applying your update function, avoiding `409 Conflict` errors when multiple reconcile events race:

```go
_, err := resource.UpdateObject(ctx, r.client, identifier,
    func(obj *v1alpha1.MyKind, exists bool) (*v1alpha1.MyKind, error) {
        obj.Status.LastObservedGeneration = obj.GetGeneration()
        obj.Status.State = "Ready"
        obj.Status.Message = ""
        return obj, nil
    },
    resource.UpdateOptions{Subresource: "status"},
)
```

Do **not** use `client.Update` for status — it sends the full object and races with spec changes made by users.

## Generation-based skip

Check `LastObservedGeneration` at the top of the reconcile function to avoid re-processing unchanged resources:

```go
if obj.GetGeneration() == obj.Status.LastObservedGeneration {
    return operator.ReconcileResult{}, nil
}
```

## `ReconcileOptions`

Control informer behavior via `BasicReconcileOptions` on the `AppManagedKind` entry:

```go
{
    Kind:       mykindv1alpha1.MyKindKind(),
    Reconciler: reconciler,
    ReconcileOptions: simple.BasicReconcileOptions{
        Namespace:      "my-namespace",          // watch one namespace; default is all
        LabelFilters:   []string{"env=prod"},    // only reconcile matching resources
        FieldSelectors: []string{"status.phase=Running"},
        UsePlain:       false,                   // false = wrap in OpinionatedReconciler (default; manages finalizers)
    },
},
```

`UsePlain: false` (the default) wraps your reconciler in `OpinionatedReconciler`, which manages finalizers automatically so the SDK can guarantee clean deletion.

## References

- [`references/watchers.md`](references/watchers.md) — `Watcher` alternative (event-style Add/Update/Delete callbacks) + decision matrix for watcher vs reconciler
- [`references/unmanaged-kinds.md`](references/unmanaged-kinds.md) — `UnmanagedKinds` for reconciling resources your app doesn't own, with `UseOpinionated: false` guidance and common failure modes
- [`references/registration.md`](references/registration.md) — full `app.go` wiring (client setup, multi-version registration, `ValidateManifest`) + common failure modes

## External resources

- [grafana-app-sdk GitHub](https://github.com/grafana/grafana-app-sdk)
- [operator package docs](https://pkg.go.dev/github.com/grafana/grafana-app-sdk/operator)
