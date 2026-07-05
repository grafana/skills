# Custom routes in CUE

Routes can be defined at two levels. Both require corresponding Go handlers registered in `app.go`.

## Kind-level routes

```cue
MyKind: {
    kind: "MyKind"
    schema: { ... }

    routes: {
        "/actions/process": {
            "POST": {
                name: "processMyKind"   // unique within version; must start with a k8s verb
                request: {
                    body: {
                        reason: string
                    }
                }
                response: {
                    jobId:  string
                    status: string
                }
            }
        }
    }
}
```

## Version-level routes

```cue
versions: {
    "v1alpha1": {
        routes: {
            namespaced: {
                "/summary": {
                    "GET": {
                        name: "getNamespacedSummary"
                        response: { count: int }
                    }
                }
            }
            cluster: {
                "/health": {
                    "GET": {
                        name: "getHealth"
                        response: { status: string }
                    }
                }
            }
        }
    }
}
```

## After adding routes

Run `grafana-app-sdk generate` — routes are included in the AppManifest and `ValidateManifest` will fail if a Go handler is missing in `app.go`.

If the generate step fails with `route handler missing`, register the handler in `app.go`:

```go
app.RegisterCustomRouteHandler("processMyKind", processHandler)
```

…and re-run `generate`.
