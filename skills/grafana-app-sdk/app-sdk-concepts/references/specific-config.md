# App-specific configuration (`SpecificConfig`)

Apps pass structured configuration through `app.Config.SpecificConfig`. This is how the registration layer (`register.go`) passes feature flags or runtime settings into `New`.

```go
// pkg/app/config.go
type AppSpecificConfig struct {
    EnableReconciler bool
    SomeFeatureFlag  bool
}

// pkg/app/app.go — read it in New()
func New(cfg app.Config) (app.App, error) {
    appCfg, _ := cfg.SpecificConfig.(*AppSpecificConfig)
    if appCfg != nil && appCfg.EnableReconciler {
        // wire up reconciler
    }
    // ...
}

// pkg/registry/apps/<name>/register.go — populate from Grafana config
specificConfig := &app.AppSpecificConfig{
    EnableReconciler: features.IsEnabled(featuremgmt.FlagMyAppReconciler),
}
provider := simple.NewAppProvider(manifestdata.LocalManifest(), specificConfig, app.New)
```

Use `SpecificConfig` for anything that varies by environment or feature flag — never hardcode it in `New`.
