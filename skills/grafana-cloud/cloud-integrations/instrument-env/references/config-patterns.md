# Alloy configuration patterns (base config + service → exporter / log source)

## Base: the Grafana Cloud default standalone config

Every standalone Alloy install starts from the default config Grafana Cloud publishes for its
onboarding flow. **Always fetch it fresh from the canonical URL at generation time — never
copy a snapshot verbatim** into this skill or into generated configs; the published file is
the source of truth and changes as onboarding evolves:

```bash
curl -fsSL https://storage.googleapis.com/cloud-onboarding/alloy/config/config.alloy
```

What the base contains (as reviewed — re-verify against the fetched copy each run):

- **Self-monitoring pipeline** (`alloy_check`): `prometheus.exporter.self` →
  `discovery.relabel` (sets `instance` and `alloy_hostname` from `constants.hostname`, and
  `job = "integrations/alloy-check"`) → `prometheus.scrape` → a `prometheus.relabel`
  keep-filter that forwards only a small set of Alloy health metrics.
- **Egress blocks**: `prometheus.remote_write "metrics_service"` and
  `loki.write "grafana_cloud_loki"`, each authenticating with `basic_auth` — username is the
  hosted instance ID, password is `sys.env("GCLOUD_RW_API_KEY")` (token stays out of the file).
- **Placeholders** to substitute before deploying: `{GCLOUD_HOSTED_METRICS_URL}`,
  `{GCLOUD_HOSTED_METRICS_ID}`, `{GCLOUD_HOSTED_LOGS_URL}`, `{GCLOUD_HOSTED_LOGS_ID}`,
  `{GCLOUD_SCRAPE_INTERVAL}`. The [install script](install-linux-vm.md) does this with `sed`;
  do the same when deploying the config by other means.

The base covers **only Alloy self-metrics** — exactly the "self-metrics only" coverage level
the enumerate-env skill reports. Instrumenting the discovered services means
**appending components to this base**, never rewriting it:

- new metrics components forward to the existing
  `prometheus.remote_write.metrics_service.receiver`,
- new log components forward to the existing `loki.write.grafana_cloud_loki.receiver`,
- never duplicate the `remote_write` / `loki.write` egress blocks — reuse the base's.

## Service → component snippets

The mapping from a detected service to its Alloy component is driven by Grafana Cloud's
pre-built integrations: match each enumerated service to an integration slug and append its
snippets, per [install-linux-vm.md](install-linux-vm.md) ("Match enumerated services to
pre-built integrations"). The `enumerate-env` skill's Step 3 table lists the service →
exporter pairings (mysql/mariadb → `prometheus.exporter.mysql`, postgres →
`prometheus.exporter.postgres`, redis → `prometheus.exporter.redis`, host →
`prometheus.exporter.unix`, an app's `/metrics` → `prometheus.scrape`, OTel apps →
`otelcol.receiver.*`). Services with no matching integration are configured by hand from the
component reference docs those integrations link to.
