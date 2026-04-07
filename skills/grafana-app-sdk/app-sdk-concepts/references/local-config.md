# Local Development Configuration

The local development configuration when using `grafana-app-sdk project local generate` (or `make local/up` in the generated Makefile) can be configured via `local/config.yaml`. A full example of this configuration file with comments looks like:
```yaml
# Port used to bind services to localhost, for example, grafana will be available at http://grafana.k3d.localhost:9999
port: 9999
# Port used for the kubernetes APIServer on localhost
kubePort: 8556
# Pre-configured datasources to install on grafana. For custom-configuration datasources, use `datasourceConfigs`
datasources:
  - cortex
  - tempo
  - loki
# Plugin JSON data, as key/value pairs
pluginJson:
  foo: bar
# Plugin Secure JSON data. By default, the `kubeconfig` and `kubenamespace` values will be added in the generated YAML.
# You can overwrite those values by specifying them here instead.
pluginSecureJson:
  baz: foo
# Standalone operator docker image. Leave this empty to not deploy an operator
operatorImage: "myapp:latest"
# Governs whether the local setup generates kubernetes manifests for varying kinds of webhooks attached to your operator and each CRD
webhooks:
  # The port the operator exposes an HTTPS server with the webhook endpoint(s) on
  port: 8443
# Non-standard or additional datasources you want to automatically include in grafana's provisioned list
# The actual datasources need to be set up manually (arbitrary kubernetes yamls can be added to the local setup via the 'additional' folder),
# but you can predefine the connection details so they'll be added to the local grafana.
datasourceConfigs:
# Here is an example cortex config
#  - access: proxy
#    editable: false
#    name: "my-cortex-datasource"
#    type: prometheus
#    uid: "my-cortex-datasource"
#    url: "http://cortex.default.svc.cluster.local:9009/api/prom"
# Here is an example with jsonData (e.g., for BigQuery)
#  - access: proxy
#    editable: true
#    name: "BigQuery"
#    type: grafana-bigquery-datasource
#    uid: "my-bigquery-datasource"
#    jsonData:
#      authenticationType: gce
#      defaultProject: my-project
#
# Toggle the generating of the grafana deployments, if you want to control these elsewhere
generateGrafanaDeployment: true

# which grafana image to use
grafanaImage: grafana/grafana-enterprise:12.0.0

# Install plugins from other sources (URLS). See https://grafana.com/docs/grafana/latest/setup-grafana/configure-docker/#install-plugins-from-other-sources
grafanaInstallPlugins: ""

# You can mount additional volumes from the local disk (aside from the already-mounted ./local/mounted-files) by specifying them here
# These volumes are mounted into the k3d node. To also mount them into the Grafana container, use grafanaVolumeMounts.
additionalVolumeMounts:
#  - sourcePath: "./local/other" # Paths starting with a ./ or no leading slash are relative to the project root. Start with / for an absolute path
#    mountPath: "/tmp/k3d/other" # The destination volume path. Best practice is to use /tmp/k3d as the starting point. The default volume mount for ./local/mounted-files is /tmp/k3d/mounted-files

# Additional environment variables to add to the Grafana container
grafanaEnvVars:
#  - name: "GOOGLE_APPLICATION_CREDENTIALS"
#    value: "/gcloud/application_default_credentials.json"

# Additional volume mounts to add to the Grafana container
# The hostPath should reference a path from additionalVolumeMounts (the k3d node mount path)
grafanaVolumeMounts:
#  - name: "gcloud-credentials"
#    mountPath: "/gcloud"
#    hostPath: "/tmp/k3d/gcloud"

# Example: Full BigQuery setup with gcloud credentials
# additionalVolumeMounts:
#   - sourcePath: "~/.config/gcloud"  # ~ is expanded to home directory
#     mountPath: "/tmp/k3d/gcloud"
# grafanaEnvVars:
#   - name: "GOOGLE_APPLICATION_CREDENTIALS"
#     value: "/gcloud/application_default_credentials.json"
# grafanaVolumeMounts:
#   - name: "gcloud-credentials"
#     mountPath: "/gcloud"
#     hostPath: "/tmp/k3d/gcloud"
# datasourceConfigs:
#   - access: proxy
#     editable: true
#     name: "BigQuery"
#     type: grafana-bigquery-datasource
#     uid: "my-bigquery-datasource"
#     jsonData:
#       authenticationType: gce
#       defaultProject: my-project
# grafanaInstallPlugins: "grafana-bigquery-datasource"
```