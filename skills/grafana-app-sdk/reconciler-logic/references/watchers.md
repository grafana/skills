# Watcher — alternative to Reconciler

A `Watcher` receives distinct `Add` / `Update` / `Delete` callbacks instead of a unified reconcile loop. Reconcilers are the preferred pattern; the default scaffolding still uses watchers because they're simpler for event-style handling.

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

## Picking watcher vs reconciler

| Use a Reconciler when… | Use a Watcher when… |
|---|---|
| Logic is mostly "drive toward desired state" | Each event needs distinct handling (e.g. notify on Create, archive on Delete) |
| You want generation-based skip + status updates | You don't track convergence to desired state |
| You need RequeueAfter for polling external systems | You don't need scheduled re-runs |

Register the watcher in `AppManagedKind` using the `Watcher` field instead of `Reconciler` (see [references/registration.md](registration.md)).
