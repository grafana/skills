# Deployment Mode Reference

## Standalone Operator

The app runs as a standalone Kubernetes operator binary with its own webhook server.

### Init steps
```bash
grafana-app-sdk project init github.com/example/my-app
grafana-app-sdk project component add operator  # adds operator stubs (confirm with user first)
```

### Project structure after init + operator scaffold
```
my-app/
├── kinds/
├── pkg/
│   ├── generated/     # generated — do not edit
│   └── app/
│       └── app.go     # implement app.App interface here
├── cmd/
│   └── operator/
│       └── main.go    # operator entrypoint
├── go.mod
└── Makefile
```

### Runtime
- Runs as a Kubernetes operator
- Stands up its own admission webhook server
- Kubernetes routes admission requests to the webhook server via `ValidatingWebhookConfiguration` / `MutatingWebhookConfiguration`
- Reconcilers watch the Kubernetes API for resource changes

### Deployment
- Build a container image (`make build`)
- Deploy to Kubernetes with generated CRDs and webhook config

---

## grafana/apps

The app is a submodule inside the `github.com/grafana/grafana` repository's `apps/` directory.

**Only available inside the Grafana repo or a fork.** The repo is identified by the presence of `apps/` and `pkg/registry/apps/` at the git root. When inside the Grafana repo, this is the only available deployment mode.

The `grafana-app-sdk:init` command prompts for the app directory name (e.g. `myapp`) and derives the module path automatically as `github.com/grafana/grafana/apps/<app-name>` (adjusted for fork module names).

### Init steps
```bash
# From the grafana repo root — create and enter the app subdirectory
mkdir -p apps/my-app
cd apps/my-app
grafana-app-sdk project init github.com/grafana/grafana/apps/my-app

# Delete everything except:
#   kinds/  pkg/  go.mod  go.sum
rm -rf cmd/ config/ ...  # remove generated dirs not needed

# Copy Makefile from example (run from repo root)
cp apps/example/Makefile apps/my-app/Makefile
```

### Wiring into Grafana

**1. Create `pkg/registry/apps/my-app/register.go`:**
```go
package myapp

import (
    "github.com/grafana/grafana-app-sdk/app"
    "github.com/grafana/grafana/apps/my-app/pkg/apis/manifestdata"
    appsdkapiserver "github.com/grafana/grafana-app-sdk/k8s/apiserver"
    "github.com/grafana/grafana/pkg/services/featuremgmt"
	"github.com/grafana/grafana/pkg/setting"
)

var (
	_ appsdkapiserver.AppInstaller = (*AppInstaller)(nil)
)

type AppInstaller struct {
	appsdkapiserver.AppInstaller
	cfg *setting.Cfg
}

// Uncomment to add an authorizer for the app
// func (e AppInstaller) GetAuthorizer() authorizer.Authorizer {
//	return nil
// }

func RegisterAppInstaller(
	cfg *setting.Cfg,
	features featuremgmt.FeatureToggles,
) (*AppInstaller, error) {
	installer := &AppInstaller{
		cfg: cfg,
	}
    // specificConfig is any app-specific config, it should be a type defined in the myapp package
    var specificConfig any
    // Provider is the app provider, which contains the AppManifest, app-specific-config, and the New function for the app
	provider := simple.NewAppProvider(manifestdata.LocalManifest(), specificConfig, exampleapp.New)

	// appConfig is used alongside the provider for registrion.
	// Most of the data is redunant, this may be more optimized in the future.
	appConfig := app.Config{
		KubeConfig:     restclient.Config{}, // this will be overridden by the installer's InitializeApp method
		ManifestData:   *manifestdata.LocalManifest().ManifestData,
		SpecificConfig: specificConfig,
	}
	// NewDefaultInstaller gets us the installer we need to underly the AppInstaller type.
	// It does all the hard work of installing our app to the grafana API server
	i, err := appsdkapiserver.NewDefaultAppInstaller(provider, appConfig, manifestdata.NewGoTypeAssociator())
	if err != nil {
		return nil, err
	}
	installer.AppInstaller = i

	return installer, nil
}

```

**2. Add to `pkg/registry/apps/apps.go`:**
```go
func ProvideAppInstallers(...) []app.Installer {
    return []app.Installer{
        // ... existing apps ...
        myapp.RegisterAppInstaller(),
    }
}
```

**3. Add to the WireSet in `pkg/registry/apps/wireset.go`**
```go
var WireSet = wire.NewSet(
	// ... existing apps ...
	myapp.RegisterAppInstaller,
)
```

### Runtime
- App is embedded in Grafana's API server
- Admission handlers are auto-registered as Kubernetes in-process plugins — no separate webhook server
- Reconcilers run inside the Grafana process

### Enable in development
Add to `conf/custom.ini`:
```ini
[feature_toggles]
grafanaAPIServer = true

[grafana-apiserver]
enabled = true
```

Reference: `github.com/grafana/grafana/apps/example/README.md`

---

## Frontend-Only

No backend code. The app has kind definitions and generated TypeScript types, but no Go reconcilers or admission handlers.

### Init steps
```bash
grafana-app-sdk project init github.com/example/my-app
# No operator or backend component — skip those steps
grafana-app-sdk project component add frontend  # optional: scaffold the frontend plugin
```

### Use case
- Apps that only need to read/write resources via the Kubernetes API from the frontend
- Dashboards, configuration UIs, or read-only viewers
- The Kubernetes API server handles storage; the app provides no custom admission logic

### Code generation
Typically only `frontend.enabled: true` in kind codegen config. Go backend types can be disabled to avoid generating unused code.
