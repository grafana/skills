# Alloy bootstrap configuration

For Alloy to receive remote config from Fleet Management it needs the `remotecfg` block locally.

## Standalone Alloy

```alloy
// /etc/alloy/bootstrap.alloy
remotecfg {
  url = "https://<FLEET_MANAGEMENT_HOST>"

  basic_auth {
    username = "<STACK_ID>"
    password = env("GRAFANA_CLOUD_API_KEY")
  }

  poll_frequency = "1m"

  attributes = {
    "env"    = env("ENVIRONMENT"),
    "team"   = "platform",
    "region" = env("AWS_REGION"),
  }
}
```

## Kubernetes (grafana/alloy Helm chart)

```yaml
alloy:
  configMap:
    content: |
      remotecfg {
        url = "https://<FLEET_MANAGEMENT_HOST>"
        basic_auth {
          username = "<STACK_ID>"
          password = env("GRAFANA_CLOUD_API_KEY")
        }
        poll_frequency = "1m"
        attributes = {
          "env"     = "production",
          "cluster" = env("CLUSTER_NAME"),
        }
      }
  extraEnv:
    - name: GRAFANA_CLOUD_API_KEY
      valueFrom:
        secretKeyRef:
          name: grafana-cloud-credentials
          key:  api-key
```

## Grafana Assistant Fleet Management tools

- `fleetManagementRead` — list collectors and pipelines
- `fleetManagementWrite` — update pipeline configurations
- `alloyConfigValidation` — validate Alloy River syntax
