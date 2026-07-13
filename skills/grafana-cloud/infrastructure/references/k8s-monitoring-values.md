# `k8s-monitoring` Helm values reference

## Full values.yaml

```yaml
cluster:
  name: production-us-east

externalServices:
  prometheus:
    host: https://prometheus-prod-xx.grafana.net
    basicAuth:
      username: "123456"
      password: { secretName: grafana-cloud-secret, secretKey: api-key }
  loki:
    host: https://logs-prod-xx.grafana.net
    basicAuth:
      username: "234567"
      password: { secretName: grafana-cloud-secret, secretKey: api-key }
  tempo:
    host: https://tempo-prod-xx.grafana.net:443
    basicAuth:
      username: "345678"
      password: { secretName: grafana-cloud-secret, secretKey: api-key }

metrics:
  enabled: true
  cost: { enabled: true }            # Kubernetes cost monitoring
  podMonitors:     { enabled: true }
  serviceMonitors: { enabled: true }
  kube-state-metrics: { enabled: true }
  node-exporter:      { enabled: true }
  cadvisor:           { enabled: true }

logs:
  pod_logs:       { enabled: true }
  cluster_events: { enabled: true }

traces:   { enabled: true }
profiles: { enabled: false }

receivers:
  grpc: { enabled: true, port: 4317 }
  http: { enabled: true, port: 4318 }
```

## Useful Kubernetes PromQL

```promql
# CPU usage by pod
sum(rate(container_cpu_usage_seconds_total{namespace="$namespace", container!=""}[5m])) by (pod)

# Memory by pod
sum(container_memory_working_set_bytes{namespace="$namespace", container!=""}) by (pod)

# Node CPU pressure
1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance)

# Pod restarts
increase(kube_pod_container_status_restarts_total[1h])

# Deployment readiness
kube_deployment_status_replicas_ready / kube_deployment_spec_replicas

# PVC usage
kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes
```

## Pre-built dashboards (grafana.com IDs)

- Kubernetes / Cluster — **15520**
- Kubernetes / Namespace — **15521**
- Kubernetes / Pod — **15522**
- Node Exporter Full — **1860**
- cAdvisor — **14282**

## Infrastructure alert rules

```yaml
groups:
  - name: kubernetes-alerts
    rules:
      - alert: PodCrashLooping
        expr: rate(kube_pod_container_status_restarts_total[15m]) * 60 * 15 > 0
        for: 5m
        labels: { severity: warning }
        annotations:
          summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} crash looping"

      - alert: NodeMemoryPressure
        expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.1
        for: 5m
        labels: { severity: critical }
        annotations:
          summary: "Node {{ $labels.instance }} low memory (<10% free)"

      - alert: PersistentVolumeAlmostFull
        expr: kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes < 0.1
        for: 5m
        labels: { severity: warning }
        annotations:
          summary: "PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} almost full"
```
