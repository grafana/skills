# OTel Collector Configuration Examples

## Grafana Alloy

Grafana Alloy uses a River-based configuration language (`.alloy` files).
It is the recommended collector distribution from Grafana Labs.

### Installation

```bash
# macOS
brew install grafana/grafana/alloy

# Linux (Debian/Ubuntu)
sudo apt-get install alloy

# Docker
docker run -v /path/to/config.alloy:/etc/alloy/config.alloy \
  -p 4317:4317 -p 4318:4318 \
  grafana/alloy run /etc/alloy/config.alloy
```

### Complete Application Observability Config

Save as `config.alloy`:

```alloy
// =========================================
// OTLP Receiver - accepts telemetry from apps
// =========================================
otelcol.receiver.otlp "default" {
  grpc {
    endpoint = "0.0.0.0:4317"
  }
  http {
    endpoint = "0.0.0.0:4318"
  }

  output {
    metrics = [otelcol.processor.resourcedetection.default.input]
    logs    = [otelcol.processor.resourcedetection.default.input]
    traces  = [otelcol.processor.resourcedetection.default.input]
  }
}

// =========================================
// Resource Detection - enrich with host/cloud metadata
// =========================================
otelcol.processor.resourcedetection "default" {
  detectors = ["env", "system", "docker"]

  system {
    hostname_sources = ["os"]
  }

  output {
    metrics = [otelcol.processor.transform.drop_unneeded_resource_attributes.input]
    logs    = [otelcol.processor.transform.drop_unneeded_resource_attributes.input]
    traces  = [otelcol.processor.transform.drop_unneeded_resource_attributes.input]
  }
}

// =========================================
// Transform - remove noisy/unnecessary attributes
// =========================================
otelcol.processor.transform "drop_unneeded_resource_attributes" {
  error_mode = "ignore"

  trace_statements {
    context = "resource"
    statements = [
      "delete_key(attributes, \"process.pid\")",
      "delete_key(attributes, \"process.runtime.description\")",
      "delete_key(attributes, \"process.runtime.name\")",
      "delete_key(attributes, \"process.runtime.version\")",
    ]
  }

  metric_statements {
    context = "resource"
    statements = [
      "delete_key(attributes, \"process.pid\")",
    ]
  }

  log_statements {
    context = "resource"
    statements = [
      "delete_key(attributes, \"process.pid\")",
    ]
  }

  output {
    metrics = [otelcol.connector.host_info.default.input]
    logs    = [otelcol.processor.batch.default.input]
    traces  = [otelcol.connector.host_info.default.input]
  }
}

// =========================================
// Host Info Connector - generate host metrics from traces
// =========================================
otelcol.connector.host_info "default" {
  host_identifiers = ["host.name"]

  output {
    metrics = [otelcol.processor.batch.default.input]
  }
}

// =========================================
// Batch Processor - group data for efficiency
// =========================================
otelcol.processor.batch "default" {
  output {
    metrics = [otelcol.exporter.otlphttp.grafana_cloud.input]
    logs    = [otelcol.exporter.otlphttp.grafana_cloud.input]
    traces  = [otelcol.exporter.otlphttp.grafana_cloud.input]
  }
}

// =========================================
// OTLP HTTP Exporter - send to Grafana Cloud
// =========================================
otelcol.exporter.otlphttp "grafana_cloud" {
  client {
    endpoint = env("GRAFANA_CLOUD_OTLP_ENDPOINT")

    auth = otelcol.auth.basic.grafana_cloud.handler
  }
}

otelcol.auth.basic "grafana_cloud" {
  username = env("GRAFANA_CLOUD_INSTANCE_ID")
  password = env("GRAFANA_CLOUD_API_KEY")
}
```

### Run Alloy

```bash
# Set required environment variables
export GRAFANA_CLOUD_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp
export GRAFANA_CLOUD_INSTANCE_ID=123456
export GRAFANA_CLOUD_API_KEY=glc_eyJ...

# Run
alloy run config.alloy
```

### Minimal Config (no processors)

```alloy
otelcol.receiver.otlp "default" {
  grpc { endpoint = "0.0.0.0:4317" }
  http { endpoint = "0.0.0.0:4318" }
  output {
    metrics = [otelcol.exporter.otlphttp.cloud.input]
    logs    = [otelcol.exporter.otlphttp.cloud.input]
    traces  = [otelcol.exporter.otlphttp.cloud.input]
  }
}

otelcol.exporter.otlphttp "cloud" {
  client {
    endpoint = env("GRAFANA_CLOUD_OTLP_ENDPOINT")
    auth     = otelcol.auth.basic.cloud.handler
  }
}

otelcol.auth.basic "cloud" {
  username = env("GRAFANA_CLOUD_INSTANCE_ID")
  password = env("GRAFANA_CLOUD_API_KEY")
}
```

---

## Grafana Alloy - Head-Based Sampling

```alloy
otelcol.receiver.otlp "default" {
  grpc { endpoint = "0.0.0.0:4317" }
  http { endpoint = "0.0.0.0:4318" }
  output {
    traces = [otelcol.processor.probabilistic_sampler.default.input]
    metrics = [otelcol.exporter.otlphttp.cloud.input]
    logs    = [otelcol.exporter.otlphttp.cloud.input]
  }
}

otelcol.processor.probabilistic_sampler "default" {
  sampling_percentage = 10   // keep 10% of traces

  output {
    traces = [otelcol.exporter.otlphttp.cloud.input]
  }
}

otelcol.exporter.otlphttp "cloud" {
  client {
    endpoint = env("GRAFANA_CLOUD_OTLP_ENDPOINT")
    auth     = otelcol.auth.basic.cloud.handler
  }
}

otelcol.auth.basic "cloud" {
  username = env("GRAFANA_CLOUD_INSTANCE_ID")
  password = env("GRAFANA_CLOUD_API_KEY")
}
```

---

## Grafana Alloy - Tail-Based Sampling

Tail sampling makes decisions after all spans of a trace are collected (requires buffering).
Useful for: always keeping errors, slow requests, or specific services.

```alloy
otelcol.receiver.otlp "default" {
  grpc { endpoint = "0.0.0.0:4317" }
  http { endpoint = "0.0.0.0:4318" }
  output {
    traces  = [otelcol.processor.tail_sampling.default.input]
    metrics = [otelcol.exporter.otlphttp.cloud.input]
    logs    = [otelcol.exporter.otlphttp.cloud.input]
  }
}

otelcol.processor.tail_sampling "default" {
  // Wait this long after seeing first span before deciding
  decision_wait               = "10s"
  num_traces                  = 100000
  expected_new_traces_per_sec = 100

  // Keep ALL error traces
  policy {
    name = "keep-errors"
    type = "status_code"
    status_code {
      status_codes = ["ERROR"]
    }
  }

  // Keep slow traces (> 500ms)
  policy {
    name = "keep-slow-traces"
    type = "latency"
    latency {
      threshold_ms = 500
    }
  }

  // Sample 10% of remaining
  policy {
    name = "probabilistic-sample"
    type = "probabilistic"
    probabilistic {
      sampling_percentage = 10
    }
  }

  output {
    traces = [otelcol.exporter.otlphttp.cloud.input]
  }
}

otelcol.exporter.otlphttp "cloud" {
  client {
    endpoint = env("GRAFANA_CLOUD_OTLP_ENDPOINT")
    auth     = otelcol.auth.basic.cloud.handler
  }
}

otelcol.auth.basic "cloud" {
  username = env("GRAFANA_CLOUD_INSTANCE_ID")
  password = env("GRAFANA_CLOUD_API_KEY")
}
```

---

## Grafana Alloy - Kubernetes (Helm)

### Helm Values (k8s-monitoring chart)

```yaml
# values.yaml
cluster:
  name: my-cluster

externalServices:
  prometheus:
    host: https://prometheus-us-central1.grafana.net
    basicAuth:
      username: "123456"
      password: "${GRAFANA_API_KEY}"
  loki:
    host: https://logs-us-central1.grafana.net
    basicAuth:
      username: "123456"
      password: "${GRAFANA_API_KEY}"
  tempo:
    host: https://tempo-us-central1.grafana.net
    basicAuth:
      username: "123456"
      password: "${GRAFANA_API_KEY}"

receivers:
  otlp:
    enabled: true
    grpc:
      enabled: true
    http:
      enabled: true

opencost:
  enabled: false
```

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm upgrade --install k8s-monitoring grafana/k8s-monitoring \
  --namespace monitoring --create-namespace \
  -f values.yaml
```

---

## Upstream OpenTelemetry Collector

For environments where Grafana Alloy cannot be used.

### Installation

```bash
# Download otelcol-contrib (includes all components)
curl -L https://github.com/open-telemetry/opentelemetry-collector-releases/releases/latest/download/otelcol-contrib_linux_amd64.tar.gz | tar xz

# Docker
docker run -v /path/to/config.yaml:/etc/otelcol-contrib/config.yaml \
  -p 4317:4317 -p 4318:4318 \
  otel/opentelemetry-collector-contrib:latest
```

### Complete config.yaml

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  # Detect host/cloud resource attributes
  resourcedetection:
    detectors: [env, system, docker]
    system:
      hostname_sources: [os]
    timeout: 2s

  # Remove noisy attributes
  transform:
    error_mode: ignore
    trace_statements:
      - context: resource
        statements:
          - delete_key(attributes, "process.pid")
          - delete_key(attributes, "process.runtime.description")

  # Batch for efficiency
  batch:
    send_batch_size: 1000
    timeout: 10s

  # Memory limiter to prevent OOM
  memory_limiter:
    check_interval: 5s
    limit_mib: 512
    spike_limit_mib: 128

exporters:
  # Send to Grafana Cloud
  otlphttp/grafana:
    endpoint: ${env:GRAFANA_CLOUD_OTLP_ENDPOINT}
    auth:
      authenticator: basicauth/grafana

  # Debug - log to console
  debug:
    verbosity: detailed

extensions:
  basicauth/grafana:
    client_auth:
      username: ${env:GRAFANA_CLOUD_INSTANCE_ID}
      password: ${env:GRAFANA_CLOUD_API_KEY}

  health_check:
    endpoint: 0.0.0.0:13133

service:
  extensions: [basicauth/grafana, health_check]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, resourcedetection, transform, batch]
      exporters: [otlphttp/grafana]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, resourcedetection, batch]
      exporters: [otlphttp/grafana]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, resourcedetection, batch]
      exporters: [otlphttp/grafana]
```

### Run

```bash
export GRAFANA_CLOUD_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp
export GRAFANA_CLOUD_INSTANCE_ID=123456
export GRAFANA_CLOUD_API_KEY=glc_eyJ...

./otelcol-contrib --config config.yaml
```

---

## Upstream Collector - Tail Sampling

```yaml
processors:
  tail_sampling:
    decision_wait: 10s
    num_traces: 100000
    expected_new_traces_per_sec: 100
    policies:
      - name: keep-errors
        type: status_code
        status_code:
          status_codes: [ERROR]

      - name: keep-slow
        type: latency
        latency:
          threshold_ms: 500

      - name: probabilistic
        type: probabilistic
        probabilistic:
          sampling_percentage: 10

      - name: keep-specific-service
        type: string_attribute
        string_attribute:
          key: service.name
          values: [payment-service]   # always keep

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, tail_sampling, batch]
      exporters: [otlphttp/grafana]
```

---

## Kubernetes - OTel Collector as DaemonSet

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: otelcol-config
  namespace: monitoring
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      # Collect kubelet metrics
      kubeletstats:
        collection_interval: 30s
        auth_type: serviceAccount
        endpoint: "https://${env:K8S_NODE_NAME}:10250"
        insecure_skip_verify: true

    processors:
      k8sattributes:
        auth_type: serviceAccount
        passthrough: false
        extract:
          metadata:
            - k8s.pod.name
            - k8s.pod.uid
            - k8s.deployment.name
            - k8s.namespace.name
            - k8s.node.name
        pod_association:
          - sources:
            - from: resource_attribute
              name: k8s.pod.ip
          - sources:
            - from: connection

      batch:
        send_batch_size: 1000
        timeout: 10s

    exporters:
      otlphttp/grafana:
        endpoint: ${env:GRAFANA_CLOUD_OTLP_ENDPOINT}
        auth:
          authenticator: basicauth/grafana

    extensions:
      basicauth/grafana:
        client_auth:
          username: ${env:GRAFANA_CLOUD_INSTANCE_ID}
          password: ${env:GRAFANA_CLOUD_API_KEY}

    service:
      extensions: [basicauth/grafana]
      pipelines:
        traces:
          receivers: [otlp]
          processors: [k8sattributes, batch]
          exporters: [otlphttp/grafana]
        metrics:
          receivers: [otlp, kubeletstats]
          processors: [k8sattributes, batch]
          exporters: [otlphttp/grafana]
        logs:
          receivers: [otlp]
          processors: [k8sattributes, batch]
          exporters: [otlphttp/grafana]
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: otelcol
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: otelcol
  template:
    metadata:
      labels:
        app: otelcol
    spec:
      serviceAccountName: otelcol
      containers:
      - name: otelcol
        image: otel/opentelemetry-collector-contrib:latest
        args: ["--config=/etc/otelcol/config.yaml"]
        env:
        - name: GRAFANA_CLOUD_OTLP_ENDPOINT
          valueFrom:
            secretKeyRef:
              name: grafana-cloud-creds
              key: otlp-endpoint
        - name: GRAFANA_CLOUD_INSTANCE_ID
          valueFrom:
            secretKeyRef:
              name: grafana-cloud-creds
              key: instance-id
        - name: GRAFANA_CLOUD_API_KEY
          valueFrom:
            secretKeyRef:
              name: grafana-cloud-creds
              key: api-key
        - name: K8S_NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        ports:
        - name: otlp-grpc
          containerPort: 4317
        - name: otlp-http
          containerPort: 4318
        volumeMounts:
        - name: config
          mountPath: /etc/otelcol
      volumes:
      - name: config
        configMap:
          name: otelcol-config
---
apiVersion: v1
kind: Service
metadata:
  name: otelcol
  namespace: monitoring
spec:
  selector:
    app: otelcol
  ports:
  - name: otlp-grpc
    port: 4317
    targetPort: 4317
  - name: otlp-http
    port: 4318
    targetPort: 4318
```

---

## Kubernetes - OTel Operator with Instrumentation CR

### Install Operator

```bash
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml
```

### OpenTelemetryCollector CR

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: otelcol
  namespace: monitoring
spec:
  mode: daemonset   # or deployment, statefulset, sidecar
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318

    processors:
      batch:
        send_batch_size: 1000
        timeout: 10s

    exporters:
      otlphttp/grafana:
        endpoint: ${env:GRAFANA_CLOUD_OTLP_ENDPOINT}
        headers:
          authorization: "Basic ${env:GRAFANA_CLOUD_AUTH}"

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [otlphttp/grafana]
        metrics:
          receivers: [otlp]
          processors: [batch]
          exporters: [otlphttp/grafana]
        logs:
          receivers: [otlp]
          processors: [batch]
          exporters: [otlphttp/grafana]
  env:
  - name: GRAFANA_CLOUD_OTLP_ENDPOINT
    valueFrom:
      secretKeyRef:
        name: grafana-cloud-creds
        key: otlp-endpoint
  - name: GRAFANA_CLOUD_AUTH
    valueFrom:
      secretKeyRef:
        name: grafana-cloud-creds
        key: basic-auth-base64
```

### Instrumentation CR (auto-injection)

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: grafana-instrumentation
  namespace: default
spec:
  exporter:
    endpoint: http://otelcol-collector.monitoring:4317

  propagators:
    - tracecontext
    - baggage

  sampler:
    type: parentbased_traceidratio
    argument: "0.25"   # 25% sampling

  java:
    # Use Grafana distribution
    image: us-docker.pkg.dev/grafanalabs-global/docker-grafana-opentelemetry-java-prod/grafana-opentelemetry-java:2.3.0-beta.1
    env:
    - name: OTEL_EXPORTER_OTLP_PROTOCOL
      value: grpc

  nodejs:
    env:
    - name: OTEL_EXPORTER_OTLP_PROTOCOL
      value: grpc

  python:
    env:
    - name: OTEL_EXPORTER_OTLP_PROTOCOL
      value: grpc

  dotnet:
    env:
    - name: OTEL_EXPORTER_OTLP_PROTOCOL
      value: grpc
```

### Inject into Pods

Add ONE annotation to your pod template:

```yaml
# Java
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-java: "true"

# Node.js
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-nodejs: "true"

# Python
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-python: "true"

# .NET
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-dotnet: "true"

# Use specific Instrumentation from another namespace
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-java: "monitoring/grafana-instrumentation"
```

---

## Secret Management for Grafana Cloud Credentials

```bash
# Create Kubernetes secret
kubectl create secret generic grafana-cloud-creds \
  --namespace monitoring \
  --from-literal=otlp-endpoint=https://otlp-gateway-prod-us-east-0.grafana.net/otlp \
  --from-literal=instance-id=123456 \
  --from-literal=api-key=glc_eyJ... \
  --from-literal=basic-auth-base64=$(echo -n '123456:glc_eyJ...' | base64)
```

---

## Alloy Docker Compose

```yaml
# docker-compose.yaml
services:
  alloy:
    image: grafana/alloy:latest
    ports:
      - "4317:4317"   # OTLP gRPC
      - "4318:4318"   # OTLP HTTP
      - "12345:12345" # Alloy UI
    volumes:
      - ./config.alloy:/etc/alloy/config.alloy
    command: run --server.http.listen-addr=0.0.0.0:12345 /etc/alloy/config.alloy
    environment:
      - GRAFANA_CLOUD_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp
      - GRAFANA_CLOUD_INSTANCE_ID=123456
      - GRAFANA_CLOUD_API_KEY=glc_eyJ...

  myapp:
    build: .
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy:4317
      - OTEL_EXPORTER_OTLP_PROTOCOL=grpc
      - OTEL_RESOURCE_ATTRIBUTES=service.name=myapp,service.namespace=myteam,deployment.environment=dev
    depends_on:
      - alloy
```
