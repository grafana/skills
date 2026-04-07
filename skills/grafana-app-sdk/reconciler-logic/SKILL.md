---
name: reconciler-logic
license: Apache-2.0
description: Use when the user asks to "write a reconciler", "implement a reconciler", "add business logic", "handle resource changes", "process resource events", "implement the reconcile loop", "add async processing", "write a controller", "handle create/update/delete events", "use TypedReconciler", "use a Watcher", or asks how to respond to resource state changes in a grafana-app-sdk app. Provides guidance on implementing reconciler and watcher business logic for grafana-app-sdk apps.
---

# Reconciler Logic

Reconcilers provide the asynchronous business logic layer of a grafana-app-sdk app. When a resource is created, updated, or deleted, the SDK enqueues a reconcile event. The reconciler's job is to observe the current state of the resource and take whatever actions are needed to drive the system toward the desired state.

Reconcilers run asynchronously after a resource has been persisted — they are distinct from admission handlers, which run synchronously on ingress.

## Getting Stubs

For standalone apps, generate reconciler stubs with:

```bash
grafana-app-sdk project component add operator
```

## TypedReconciler — Preferred Pattern

The preferred implementation uses `operator.TypedReconciler`, which handles type assertion and provides a strongly-typed `ReconcileFunc`:

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
    if obj.GetGeneration() == obj.Status.LastObservedGeneration && req.Action != operator.ReconcileActionDeleted {
        return operator.ReconcileResult{}, nil
    }

    log := logging.FromContext(ctx).With("name", obj.GetName(), "namespace", obj.GetNamespace())
    log.Info("reconciling", "action", operator.ResourceActionFromReconcileAction(req.Action))

    // Handle deletion
    if req.Action == operator.ReconcileActionDeleted {
        return operator.ReconcileResult{}, nil
    }

    // ... business logic ...

    // Atomic status update with conflict resolution
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

`operator.ReconcileAction` values: `ReconcileActionCreated`, `ReconcileActionUpdated`, `ReconcileActionDeleted`, `ReconcileActionResynced`.

To requeue a resource after a delay (e.g. for polling an external system), set `RequeueAfter` on the result:

```go
return operator.ReconcileResult{RequeueAfter: 10 * time.Second}, nil
```

## Status Updates with `resource.UpdateObject`

Always use `resource.UpdateObject` for status updates — it handles conflicts by fetching the latest version before applying the update function, avoiding `409 Conflict` errors common when multiple reconcile events race:

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

## Generation-Based Skip

Check `LastObservedGeneration` at the top of the reconcile function to avoid re-processing unchanged resources:

```go
if obj.GetGeneration() == obj.Status.LastObservedGeneration {
    return operator.ReconcileResult{}, nil
}
```

## ReconcileOptions

Control how the informer watches resources via `BasicReconcileOptions` on the `AppManagedKind` entry:

```go
{
    Kind:       mykindv1alpha1.MyKindKind(),
    Reconciler: reconciler,
    ReconcileOptions: simple.BasicReconcileOptions{
        Namespace:      "my-namespace",          // watch one namespace; default is all
        LabelFilters:   []string{"env=prod"},    // only reconcile matching resources
        FieldSelectors: []string{"status.phase=Running"},
        UsePlain:       false,                   // false = wrap in OpinionatedReconciler (default)
                                                 // true  = use reconciler directly, no finalizer management
    },
},
```

`UsePlain: false` (default) wraps your reconciler in the `OpinionatedReconciler`, which manages finalizers automatically to ensure clean deletion.

## Watcher — Alternative to Reconciler

A `Watcher` receives distinct `Add`, `Update`, and `Delete` callbacks instead of a unified reconcile loop:

```go
type MyKindWatcher struct {
    client resource.Client
}

func (w *MyKindWatcher) Add(ctx context.Context, obj resource.Object) error {
    typed := obj.(*v1alpha1.MyKind)
    // handle create
    return nil
}

func (w *MyKindWatcher) Update(ctx context.Context, obj, old resource.Object) error {
    typed := obj.(*v1alpha1.MyKind)
    // handle update
    return nil
}

func (w *MyKindWatcher) Delete(ctx context.Context, obj resource.Object) error {
    // handle delete
    return nil
}

func (w *MyKindWatcher) Sync(ctx context.Context, obj resource.Object) error {
    // called on resync; handle like Add if needed
    return nil
}
```

Register with `Watcher` instead of `Reconciler` in `AppManagedKind`. Reconcilers are the preferred pattern; the default scaffolding still uses watchers.

## UnmanagedKinds — Watching Related Resources

To watch a kind your app doesn't own (e.g. a ConfigMap or a kind from another app), use `UnmanagedKinds` in `AppConfig`:

```go
UnmanagedKinds: []simple.AppUnmanagedKind{
    {
        Kind:       corev1.ConfigMapKind(),
        Reconciler: &ConfigMapReconciler{},
        ReconcileOptions: simple.UnmanagedKindReconcileOptions{
            Namespace:      "my-namespace",
            LabelFilters:   []string{"app=my-app"},
            UseOpinionated: false, // don't add finalizers to unmanaged resources
        },
    },
},
```

## Registration in app.go

```go
func New(cfg app.Config) (app.App, error) {
    cfg.KubeConfig.APIPath = "/apis"

    client, err := k8s.NewClientRegistry(cfg.KubeConfig, k8s.DefaultClientConfig()).
        ClientFor(mykindv1alpha2.MyKindKind())
    if err != nil {
        return nil, fmt.Errorf("creating client: %w", err)
    }

    a, err := simple.NewApp(simple.AppConfig{
        Name:       "my-app",
        KubeConfig: cfg.KubeConfig,
        ManagedKinds: []simple.AppManagedKind{
            {
                Kind:       mykindv1alpha1.MyKindKind(),
                Validator:  NewValidator(),
                Mutator:    NewMutator(),
            },
            {
                // Attach reconciler to latest version only
                Kind:       mykindv1alpha2.MyKindKind(),
                Reconciler: NewMyKindReconciler(client),
                Validator:  NewValidator(),
                Mutator:    NewMutator(),
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

## Resources

- [grafana-app-sdk GitHub](https://github.com/grafana/grafana-app-sdk)
- [operator package docs](https://pkg.go.dev/github.com/grafana/grafana-app-sdk/operator)
