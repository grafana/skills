# Alloy Components Reference

> Index of the most commonly used Alloy components, grouped by namespace. The canonical and complete
> reference is at https://grafana.com/docs/alloy/latest/reference/components/.

Alloy components are identified by a dotted **namespace**.**name** and configured via a labeled
block. Each component has typed **arguments** (what you set) and **exports** (what other components
consume — typically `.receiver`, `.input`, `.targets`, `.output`, `.handler`, or `.content`).

## Discovery — find targets to scrape

Discovery components emit a `targets` export: an array of label maps consumed by `prometheus.scrape`,
`loki.source.*`, or `pyroscope.scrape`.

| Component                  | Purpose                                                          |
|----------------------------|------------------------------------------------------------------|
| `discovery.kubernetes`     | Pods, services, endpoints, nodes, ingresses via the K8s API      |
| `discovery.docker`         | Containers from the Docker daemon                                |
| `discovery.dockerswarm`    | Tasks/services from a Docker Swarm                               |
| `discovery.ec2`            | AWS EC2 instances                                                |
| `discovery.gce`            | GCP Compute Engine instances                                     |
| `discovery.azure`          | Azure VMs and scale sets                                         |
| `discovery.dns`            | DNS SRV/A/AAAA records                                           |
| `discovery.consul`         | Services registered in Consul                                    |
| `discovery.nomad`          | Allocations in HashiCorp Nomad                                   |
| `discovery.file`           | Targets from a JSON/YAML file (file_sd compatible)               |
| `discovery.http`           | Targets from an HTTP endpoint (http_sd compatible)               |
| `discovery.relabel`        | Apply relabeling rules to another component's `targets`          |
| `discovery.process`        | Local process listing (used with Beyla / Pyroscope eBPF)         |

```alloy
discovery.kubernetes "pods" {
  role = "pod"
}

discovery.relabel "pods" {
  targets = discovery.kubernetes.pods.targets
  rule {
    source_labels = ["__meta_kubernetes_namespace"]
    target_label  = "namespace"
  }
}
```

## Prometheus — metrics pipeline

| Component                       | Purpose                                                        |
|---------------------------------|----------------------------------------------------------------|
| `prometheus.scrape`             | Pull `/metrics` from `targets`                                 |
| `prometheus.remote_write`       | Write metrics via Prometheus remote-write protocol             |
| `prometheus.relabel`            | Add/drop/rewrite labels on metric samples                      |
| `prometheus.operator.podmonitors`     | Scrape using Prometheus Operator `PodMonitor` CRDs       |
| `prometheus.operator.servicemonitors` | Scrape using `ServiceMonitor` CRDs                       |
| `prometheus.operator.probes`          | Use `Probe` CRDs                                         |
| `prometheus.receive_http`       | Accept remote-write traffic (proxy / fan-out)                  |
| `prometheus.exporter.unix`      | Linux node metrics (node_exporter equivalent)                  |
| `prometheus.exporter.windows`   | Windows host metrics                                           |
| `prometheus.exporter.mongodb`   | MongoDB metrics                                                |
| `prometheus.exporter.mysql`     | MySQL metrics                                                  |
| `prometheus.exporter.postgres`  | PostgreSQL metrics                                             |
| `prometheus.exporter.redis`     | Redis metrics                                                  |
| `prometheus.exporter.snmp`      | SNMP-based device metrics                                      |
| `prometheus.exporter.blackbox`  | Blackbox probe (HTTP/TCP/ICMP)                                 |
| `prometheus.exporter.cloudwatch`| AWS CloudWatch metrics                                         |
| `prometheus.exporter.kafka`     | Kafka metrics                                                  |
| `prometheus.exporter.process`   | Per-process metrics                                            |

Inputs to scrape/relabel/remote_write chain via:

```
discovery.* → discovery.relabel → prometheus.scrape → prometheus.relabel → prometheus.remote_write
                                                                        (.receiver)
```

## Loki — logs pipeline

| Component                       | Purpose                                                        |
|---------------------------------|----------------------------------------------------------------|
| `loki.source.file`              | Tail log files (file_sd-style)                                 |
| `local.file_match`              | Path globs that produce targets for `loki.source.file`         |
| `loki.source.kubernetes`        | Tail Kubernetes container logs via API                         |
| `loki.source.kubernetes_events` | Stream cluster events                                          |
| `loki.source.journal`           | systemd journald                                               |
| `loki.source.docker`            | Docker container logs                                          |
| `loki.source.syslog`            | Listen for RFC5424/RFC3164 syslog                              |
| `loki.source.gcplog`            | GCP Pub/Sub logs                                               |
| `loki.source.awsfirehose`       | AWS Kinesis Data Firehose                                      |
| `loki.source.azure_event_hubs`  | Azure Event Hubs                                               |
| `loki.source.cloudflare`        | Cloudflare logpush                                             |
| `loki.source.api`               | Generic HTTP push endpoint                                     |
| `loki.echo`                     | Print received logs (debugging)                                |
| `loki.process`                  | Pipeline stages: parse, label, drop, transform                 |
| `loki.relabel`                  | Relabel without parsing                                        |
| `loki.write`                    | Push logs to Loki                                              |

Pipeline shape:

```
discovery.* → loki.source.* → loki.process → loki.write
                                          (.receiver)
```

`loki.process` stages include `stage.json`, `stage.logfmt`, `stage.regex`, `stage.labels`,
`stage.static_labels`, `stage.label_drop`, `stage.label_keep`, `stage.drop`, `stage.timestamp`,
`stage.output`, `stage.template`, `stage.multiline`, `stage.match`, and `stage.replace`.

## OpenTelemetry — `otelcol.*`

### Receivers

| Component                       | Purpose                                                        |
|---------------------------------|----------------------------------------------------------------|
| `otelcol.receiver.otlp`         | OTLP over gRPC (4317) and HTTP (4318)                          |
| `otelcol.receiver.jaeger`       | Jaeger gRPC/Thrift                                             |
| `otelcol.receiver.zipkin`       | Zipkin HTTP                                                    |
| `otelcol.receiver.prometheus`   | Convert Prometheus scrape data into OTel metrics               |
| `otelcol.receiver.loki`         | Convert Loki log data into OTel logs                           |
| `otelcol.receiver.kafka`        | Consume OTLP/JSON from Kafka                                   |
| `otelcol.receiver.opencensus`   | OpenCensus protocol                                            |
| `otelcol.receiver.vcenter`      | VMware vCenter                                                 |
| `otelcol.receiver.datadog`      | Datadog Agent traces/metrics                                   |

### Processors

| Component                                | Purpose                                              |
|------------------------------------------|------------------------------------------------------|
| `otelcol.processor.batch`                | Batch signals before export                          |
| `otelcol.processor.memory_limiter`       | Drop data if memory exceeds threshold                |
| `otelcol.processor.transform`            | OTTL-based transformation                            |
| `otelcol.processor.attributes`           | Insert/update/delete attributes                      |
| `otelcol.processor.resourcedetection`    | Add resource attributes (k8s/aws/gcp/azure)          |
| `otelcol.processor.k8sattributes`        | Enrich with k8s metadata                             |
| `otelcol.processor.filter`               | Drop telemetry matching OTTL expressions             |
| `otelcol.processor.tail_sampling`        | Trace tail sampling                                  |
| `otelcol.processor.probabilistic_sampler`| Head-based sampling                                  |
| `otelcol.processor.span`                 | Rename / extract attributes from span names          |
| `otelcol.processor.deltatocumulative`    | Convert delta to cumulative temporality              |

### Exporters

| Component                       | Purpose                                                        |
|---------------------------------|----------------------------------------------------------------|
| `otelcol.exporter.otlp`         | OTLP gRPC                                                      |
| `otelcol.exporter.otlphttp`     | OTLP HTTP                                                      |
| `otelcol.exporter.prometheus`   | Forward to `prometheus.remote_write`                           |
| `otelcol.exporter.loki`         | Forward to `loki.write`                                        |
| `otelcol.exporter.loadbalancing`| Distribute traces across endpoints (consistent hashing)        |
| `otelcol.exporter.kafka`        | Kafka producer                                                 |
| `otelcol.exporter.debug`        | Log telemetry to stderr (debugging)                            |
| `otelcol.exporter.faro`         | Frontend Observability                                         |

### Auth and extensions

| Component                       | Purpose                                                        |
|---------------------------------|----------------------------------------------------------------|
| `otelcol.auth.basic`            | HTTP basic auth handler for otelcol clients                    |
| `otelcol.auth.bearer`           | Bearer-token auth                                              |
| `otelcol.auth.headers`          | Static header auth                                             |
| `otelcol.auth.oauth2`           | OAuth2 client credentials                                      |
| `otelcol.auth.sigv4`            | AWS SigV4                                                      |
| `otelcol.connector.spanmetrics` | Generate RED metrics from spans                                |
| `otelcol.connector.servicegraph`| Build service-graph metrics from traces                        |

OTel pipeline shape:

```
otelcol.receiver.* → otelcol.processor.* → otelcol.exporter.*
                  (output{traces=, metrics=, logs=})       (.input)
```

## Pyroscope — profiles

| Component                       | Purpose                                                        |
|---------------------------------|----------------------------------------------------------------|
| `pyroscope.scrape`              | Pull pprof endpoints from targets                              |
| `pyroscope.ebpf`                | eBPF-based whole-system profiling                              |
| `pyroscope.java`                | async-profiler integration for JVMs                            |
| `pyroscope.relabel`             | Relabel profile streams                                        |
| `pyroscope.write`               | Send profiles to Pyroscope/Grafana Cloud Profiles              |
| `pyroscope.receive_http`        | Accept push from other Pyroscope clients                       |

## Beyla — eBPF auto-instrumentation

| Component                       | Purpose                                                        |
|---------------------------------|----------------------------------------------------------------|
| `beyla.ebpf`                    | Auto-generate traces/metrics from any process without code     |

## Faro — frontend telemetry

| Component                       | Purpose                                                        |
|---------------------------------|----------------------------------------------------------------|
| `faro.receiver`                 | Accept browser RUM payloads from the Faro Web SDK              |
| `otelcol.exporter.faro`         | Forward OTel data to Grafana Cloud Frontend Observability      |

## Database observability

| Component                              | Purpose                                                 |
|----------------------------------------|---------------------------------------------------------|
| `database_observability.mysql`         | Query Performance, EXPLAIN, slow-query parsing for MySQL|
| `database_observability.postgres`      | Same for PostgreSQL                                     |

## Mimir

| Component                       | Purpose                                                        |
|---------------------------------|----------------------------------------------------------------|
| `mimir.rules.kubernetes`        | Sync `PrometheusRule` CRDs into Mimir ruler                    |

## Local / remote helpers

| Component                       | Purpose                                                        |
|---------------------------------|----------------------------------------------------------------|
| `local.file`                    | Read a file, expose `.content` (watches for changes)           |
| `local.file_match`              | Glob filesystem paths into targets                             |
| `remote.http`                   | Fetch a URL, expose body as `.content`                         |
| `remote.s3`                     | Fetch an S3 object                                             |
| `remote.kubernetes.configmap`   | Read a ConfigMap value                                         |
| `remote.kubernetes.secret`      | Read a Secret value                                            |
| `remote.vault`                  | Read a HashiCorp Vault secret                                  |

## Imports / modules (top-level)

| Block                           | Purpose                                                        |
|---------------------------------|----------------------------------------------------------------|
| `import.file`                   | Pull declarations from a local file                            |
| `import.git`                    | Pull from a Git repo                                           |
| `import.http`                   | Pull from an HTTP endpoint                                     |
| `import.string`                 | Inline declarations                                            |
| `declare`                       | Define a reusable custom component                             |

## Quick reference — most common imports

```alloy
prometheus.scrape          // pull metrics
prometheus.remote_write    // ship metrics
prometheus.relabel         // filter/relabel metrics
loki.source.file           // tail files
loki.source.kubernetes     // tail pod logs
loki.process               // parse/label/drop logs
loki.write                 // ship logs
otelcol.receiver.otlp      // accept OTLP
otelcol.processor.batch    // batch
otelcol.processor.memory_limiter  // backpressure
otelcol.exporter.otlp      // ship via gRPC
otelcol.exporter.otlphttp  // ship via HTTPS
discovery.kubernetes       // k8s SD
discovery.relabel          // relabel targets
pyroscope.scrape           // scrape pprof
pyroscope.write            // ship profiles
beyla.ebpf                 // zero-code traces/metrics
```

For the full list and per-component arguments/exports, see
https://grafana.com/docs/alloy/latest/reference/components/.
