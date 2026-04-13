---
name: infrastructure
license: Apache-2.0
description: >
  Grafana Cloud infrastructure monitoring — Kubernetes monitoring, cloud provider integrations
  (AWS, Azure, GCP), host and container monitoring, infrastructure dashboards, and collector setup.
  Use when setting up Kubernetes monitoring, connecting cloud provider metrics, configuring node
  exporter or cAdvisor, setting up infrastructure dashboards, or using the k8s-monitoring Helm chart.
---

# Grafana Cloud Infrastructure Monitoring

> **Docs**: https://grafana.com/docs/grafana-cloud/monitor-infrastructure/

## Kubernetes Monitoring (k8s-monitoring Helm Chart)

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

```yaml
# values.yaml
cluster:
  name: production-us-east

externalServices:
  prometheus:
    host: https://prometheus-prod-xx.grafana.net
    basicAuth:
      username: "123456"
      password:
        secretName: grafana-cloud-secret
        secretKey: api-key
  loki:
    host: https://logs-prod-xx.grafana.net
    basicAuth:
      username: "234567"
      password:
        secretName: grafana-cloud-secret
        secretKey: api-key
  tempo:
    host: https://tempo-prod-xx.grafana.net:443
    basicAuth:
      username: "345678"
      password:
        secretName: grafana-cloud-secret
        secretKey: api-key

metrics:
  enabled: true
  cost:
    enabled: true    # Kubernetes cost monitoring
  podMonitors:
    enabled: true
  serviceMonitors:
    enabled: true
  kube-state-metrics:
    enabled: true
  node-exporter:
    enabled: true
  cadvisor:
    enabled: true

logs:
  pod_logs:
    enabled: true
  cluster_events:
    enabled: true

traces:
  enabled: true

profiles:
  enabled: false

receivers:
  grpc:
    enabled: true
    port: 4317
  http:
    enabled: true
    port: 4318
```

```bash
kubectl create secret generic grafana-cloud-secret \
  --from-literal=api-key=<your-api-key> \
  -n monitoring

helm install k8s-monitoring grafana/k8s-monitoring \
  -n monitoring --create-namespace \
  -f values.yaml
```

## Key Kubernetes Metrics

```promql
# CPU usage by pod
sum(rate(container_cpu_usage_seconds_total{
  namespace="$namespace", container!=""}[5m])) by (pod)

# Memory usage by pod
sum(container_memory_working_set_bytes{
  namespace="$namespace", container!=""}) by (pod)

# Node CPU pressure
1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance)

# Pod restarts
increase(kube_pod_container_status_restarts_total[1h])

# Deployment readiness
kube_deployment_status_replicas_ready / kube_deployment_spec_replicas

# PVC usage
kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes
```

## AWS CloudWatch Integration

```yaml
# Alloy config for AWS CloudWatch scraping
prometheus.scrape "cloudwatch" {
  targets = [{__address__ = "cloudwatch-exporter:9106"}]
  forward_to = [prometheus.remote_write.cloud.receiver]
}
```

Or use the CloudWatch datasource directly:
```yaml
# provisioning/datasources/cloudwatch.yaml
apiVersion: 1
datasources:
  - name: CloudWatch
    type: cloudwatch
    jsonData:
      defaultRegion: us-east-1
      authType: default    # uses EC2 instance role / ECS task role
      # Or explicit credentials:
      # authType: credentials
    secureJsonData:
      accessKey: AKIAIOSFODNN7EXAMPLE
      secretKey: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

## Azure Monitor Integration

```yaml
# provisioning/datasources/azure.yaml
apiVersion: 1
datasources:
  - name: Azure Monitor
    type: grafana-azure-monitor-datasource
    jsonData:
      cloudName: AzureCloud
      tenantId: your-tenant-id
      clientId: your-client-id
    secureJsonData:
      clientSecret: your-client-secret
```

## GCP / Google Cloud Monitoring

```yaml
# provisioning/datasources/google.yaml
apiVersion: 1
datasources:
  - name: Google Cloud Monitoring
    type: stackdriver
    jsonData:
      authenticationType: gce    # uses GCE metadata server
      # Or JWT:
      # authenticationType: jwt
    secureJsonData:
      privateKey: |
        { "type": "service_account", ... }
```

## Node Exporter / Linux Host Monitoring

```alloy
// Alloy config for Linux host metrics
prometheus.exporter.unix "host" {
  rootfs_path = "/"
  enable_collectors = ["cpu", "diskstats", "filesystem", "loadavg", "meminfo", "netdev", "stat", "time", "uname"]
}

prometheus.scrape "node" {
  targets    = prometheus.exporter.unix.host.targets
  forward_to = [prometheus.remote_write.cloud.receiver]
  scrape_interval = "60s"
}
```

## Docker / Container Monitoring

```alloy
// cAdvisor metrics via Alloy
prometheus.scrape "cadvisor" {
  targets = [{"__address__" = "localhost:8080"}]
  metrics_path = "/metrics"
  forward_to   = [prometheus.remote_write.cloud.receiver]
}

// Docker container logs
loki.source.docker "containers" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.docker.containers.targets
  forward_to = [loki.write.cloud.receiver]
}

discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}
```

## Common Infrastructure Dashboards (Grafana Cloud)

Pre-built dashboards available from the integrations catalog:
- **Kubernetes / Cluster** (ID: 15520)
- **Kubernetes / Namespace** (ID: 15521)  
- **Kubernetes / Pod** (ID: 15522)
- **Node Exporter Full** (ID: 1860)
- **cAdvisor** (ID: 14282)
- **AWS EC2** (via CloudWatch integration)
- **Azure VMs** (via Azure Monitor integration)

## Alerting for Infrastructure

```yaml
# Common infrastructure alert rules
groups:
  - name: kubernetes-alerts
    rules:
      - alert: PodCrashLooping
        expr: rate(kube_pod_container_status_restarts_total[15m]) * 60 * 15 > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} crash looping"

      - alert: NodeMemoryPressure
        expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Node {{ $labels.instance }} low memory (<10% free)"

      - alert: PersistentVolumeAlmostFull
        expr: kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes < 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} almost full"
```
