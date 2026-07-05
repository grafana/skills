# UnmanagedKinds — watching kinds your app doesn't own

To reconcile a kind your app doesn't own (e.g. a `ConfigMap`, or a kind owned by another app), use `UnmanagedKinds` in `AppConfig`:

```go
UnmanagedKinds: []simple.AppUnmanagedKind{
    {
        Kind:       corev1.ConfigMapKind(),
        Reconciler: &ConfigMapReconciler{},
        ReconcileOptions: simple.UnmanagedKindReconcileOptions{
            Namespace:      "my-namespace",
            LabelFilters:   []string{"app=my-app"},
            UseOpinionated: false,  // don't add finalizers to unmanaged resources
        },
    },
},
```

## Why `UseOpinionated: false` for unmanaged kinds

The `OpinionatedReconciler` adds finalizers so the SDK can guarantee clean deletion. For **managed** kinds that's correct — the app owns the resource lifecycle. For **unmanaged** kinds (resources owned by another app or the cluster itself), adding finalizers is invasive: it makes deletion of the resource dependent on your app being healthy, which can leave orphan finalizers if your app is uninstalled while resources exist.

Default to `UseOpinionated: false` for `UnmanagedKinds` unless you genuinely need finalizer-driven cleanup for the unmanaged resource.

## Common failure modes

| Symptom | Likely cause |
|---|---|
| Reconciler doesn't fire | Label filter doesn't match the resource's labels (check `kubectl get <resource> -o yaml` for labels) |
| Permission errors at startup | Your app's ServiceAccount lacks RBAC on the unmanaged kind — add a Role binding for `get`/`list`/`watch` on the kind's API group |
| Resources stuck in deletion | `UseOpinionated: true` was set; finalizer wasn't removed before app uninstall. Patch the resource to remove the finalizer manually. |
