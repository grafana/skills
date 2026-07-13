# Beyla on Kubernetes

## DaemonSet (cluster-wide)

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: beyla
  namespace: monitoring
spec:
  selector:
    matchLabels: { app: beyla }
  template:
    metadata:
      labels: { app: beyla }
    spec:
      hostPID: true                # required for eBPF
      serviceAccountName: beyla
      containers:
        - name: beyla
          image: grafana/beyla:latest
          securityContext:
            privileged: true       # or specific caps:
            # capabilities: { add: [SYS_ADMIN, SYS_PTRACE, NET_ADMIN] }
          env:
            - { name: BEYLA_OPEN_PORT,             value: "8080" }
            - { name: OTEL_EXPORTER_OTLP_ENDPOINT, value: "http://alloy:4318" }
          volumeMounts:
            - { name: sys-kernel-debug, mountPath: /sys/kernel/debug, readOnly: true }
      volumes:
        - name: sys-kernel-debug
          hostPath: { path: /sys/kernel/debug }
```

## RBAC

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: beyla, namespace: monitoring }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: { name: beyla }
rules:
  - apiGroups: [""]
    resources: [nodes, pods, services, endpoints, namespaces]
    verbs: [get, list, watch]
```

## Kubernetes auto-discovery filters

```yaml
discovery:
  services:
    - k8s_namespace: "production"     # all pods in namespace
    - k8s_pod_name: "frontend.*"      # by pod name regex
    - k8s_deployment_name: "api"      # by deployment name
    - open_port: 8080                 # any pod with that port
```

Auto-enriched span attributes:
`k8s.namespace.name`, `k8s.pod.name`, `k8s.node.name`, `k8s.deployment.name`

## Helm install

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install beyla grafana/beyla --version 1.16.7 \
  --set discovery.services[0].open_port=8080 \
  --set otelTraces.endpoint=http://tempo:4318
```
