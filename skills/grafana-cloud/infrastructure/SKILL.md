---
name: infrastructure
license: Apache-2.0
description: Ship Kubernetes, host, container, and cloud-provider telemetry into Grafana Cloud — `k8s-monitoring` Helm chart for K8s clusters (metrics + logs + traces + events + cost), Alloy `prometheus.exporter.unix` for Linux hosts, cAdvisor + Docker discovery for containers, and CloudWatch / Azure Monitor / Google Cloud Monitoring datasource setup. Use when onboarding a new cluster or VM fleet to Grafana Cloud, picking the right Helm values for K8s scraping, wiring kube-state-metrics + node-exporter + cAdvisor, alerting on `PodCrashLooping` / node memory / PVC capacity, or pulling AWS / Azure / GCP cloud metrics — even when the user says "monitor my cluster", "send K8s metrics to Grafana", "scrape EC2 metrics", "cluster pod logs", or "install the monitoring helm chart" without naming `k8s-monitoring` or Alloy.
---

# Grafana Cloud Infrastructure Monitoring

> **Docs**: https://grafana.com/docs/grafana-cloud/monitor-infrastructure/

K8s + host + container + cloud-provider telemetry, mostly via the `grafana/k8s-monitoring` Helm chart or Alloy.

## Prerequisites

- Grafana Cloud stack with Prometheus / Loki / Tempo endpoints + API key (`metrics:write`, `logs:write`, `traces:write`)
- For Kubernetes: a cluster + `helm` 3.x + `kubectl` context pointing at it
- For hosts / Docker: Alloy installed on the node

## Common Workflows

### 1. Onboard a Kubernetes cluster (k8s-monitoring chart)

```bash
# 1. Create the namespace + secret
kubectl create namespace monitoring
kubectl create secret generic grafana-cloud-secret \
  -n monitoring --from-literal=api-key=<your-api-key>

# 2. Install — values.yaml in references/k8s-monitoring-values.md
helm repo add grafana https://grafana.github.io/helm-charts && helm repo update
helm install k8s-monitoring grafana/k8s-monitoring \
  --version 4.1.4 -n monitoring -f values.yaml

# 3. Verify every pod is Running
kubectl get pods -n monitoring
# Expect alloy-*, kube-state-metrics-*, node-exporter-*, etc. all Ready.

# 4. Verify no error logs in the metrics/logs/traces Alloys
kubectl -n monitoring logs deploy/k8s-monitoring-alloy-metrics --tail=50 | grep -iE 'error|level=err' || echo "clean"

# 5. Verify telemetry landed in Grafana Cloud
#    PromQL on the metrics datasource (should be > 0):
#      sum(up{cluster="production-us-east"})
#    LogQL on Loki:
#      sum(count_over_time({cluster="production-us-east"}[5m]))
```

Full `values.yaml`, key PromQL, dashboard IDs (15520, 1860, 14282…), and alert rules: [`references/k8s-monitoring-values.md`](references/k8s-monitoring-values.md).

### 2. Monitor a Linux host

```alloy
# 1. /etc/alloy/config.alloy — see references/clouds-and-hosts.md for the full block
prometheus.exporter.unix "host"  { rootfs_path = "/" }
prometheus.scrape         "node" { targets = prometheus.exporter.unix.host.targets
                                   forward_to = [prometheus.remote_write.cloud.receiver] }
```

```bash
# 2. Reload Alloy and verify the unix exporter is up
systemctl reload alloy
curl -s http://localhost:12345/api/v0/web/components | jq '.[] | select(.id|contains("prometheus.exporter.unix"))'

# 3. Verify in Grafana Cloud — open the "Node Exporter Full" dashboard (ID 1860)
#    and pick your host from the `instance` dropdown.
```

### 3. Pull AWS / Azure / GCP metrics

Provision the datasource (full YAML in [`references/clouds-and-hosts.md`](references/clouds-and-hosts.md)), then:

```bash
# 1. After provisioning, restart Grafana to pick up the file
# 2. Verify the datasource — Grafana → Connections → Data sources → "Test"
#    Expect "Successfully queried the CloudWatch metrics API" (or equivalent).
# 3. Confirm a query — Explore → datasource → metric e.g.
#    CloudWatch namespace AWS/EC2 metric CPUUtilization, last 1h.
```

## Troubleshooting

- chart installed but no metrics in Cloud → check the `grafana-cloud-secret` `api-key` value; check Alloy logs for `401`
- `kube-state-metrics` pod Pending → likely RBAC; reapply the chart's CRDs/CRBs
- Node-exporter pod CrashLoopBackOff → typically `hostNetwork: true` collision with the host's :9100; change the port
- CloudWatch "Access denied" → IAM role missing `cloudwatch:GetMetricData`, `cloudwatch:ListMetrics`

## Resources

- [`grafana/k8s-monitoring` chart](https://github.com/grafana/k8s-monitoring-helm)
- [Monitor Infrastructure docs](https://grafana.com/docs/grafana-cloud/monitor-infrastructure/)
- [CloudWatch datasource](https://grafana.com/docs/grafana/latest/datasources/aws-cloudwatch/)
- [Azure Monitor datasource](https://grafana.com/docs/grafana/latest/datasources/azure-monitor/)
- [Google Cloud Monitoring datasource](https://grafana.com/docs/grafana/latest/datasources/google-cloud-monitoring/)
