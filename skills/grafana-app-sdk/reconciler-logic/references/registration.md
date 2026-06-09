# Registration in `app.go`

How to wire your reconciler into the app's `New` function.

```go
func New(cfg app.Config) (app.App, error) {
    cfg.KubeConfig.APIPath = "/apis"

    // 1. Build a client for the kind your reconciler operates on
    client, err := k8s.NewClientRegistry(cfg.KubeConfig, k8s.DefaultClientConfig()).
        ClientFor(mykindv1alpha2.MyKindKind())
    if err != nil {
        return nil, fmt.Errorf("creating client: %w", err)
    }

    // 2. Register the kind with reconciler attached to the latest version only
    a, err := simple.NewApp(simple.AppConfig{
        Name:       "my-app",
        KubeConfig: cfg.KubeConfig,
        ManagedKinds: []simple.AppManagedKind{
            {
                // Older version: validation + mutation only
                Kind:      mykindv1alpha1.MyKindKind(),
                Validator: NewValidator(),
                Mutator:   NewMutator(),
            },
            {
                // Latest version: validation + mutation + reconciler
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

    // 3. Validate the AppManifest matches what's registered (catches missing route handlers etc.)
    if err = a.ValidateManifest(cfg.ManifestData); err != nil {
        return nil, fmt.Errorf("app manifest validation failed: %w", err)
    }
    return a, nil
}
```

## Why attach the reconciler only to the latest version

With multi-version kinds, the reconciler should only fire on the canonical/latest version. The SDK auto-converts incoming objects via the conversion webhook, so reconciling v1alpha1 and v1alpha2 separately would double-reconcile the same resource.

## Common failure modes

| Symptom | Likely cause |
|---|---|
| `app manifest validation failed: route handler missing` | A `routes:` entry in CUE has no Go handler registered. Add `app.RegisterCustomRouteHandler("<routeName>", handler)` before `ValidateManifest`. |
| Reconciler doesn't fire on resource creates | The reconciler is attached to the wrong version, or `UsePlain: true` was set on `BasicReconcileOptions` and finalizers aren't being managed. |
| `error creating client: ...` | Wrong API path or kube config — check `cfg.KubeConfig.APIPath = "/apis"` is set before building the client. |
