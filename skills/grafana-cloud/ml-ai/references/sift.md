# Sift — automated root cause analysis

Free for all Grafana Cloud accounts.

## 8 analysis types

| Analysis | What it checks |
|----------|---------------|
| **Error Pattern Logs** | Clusters log errors by pattern, ranks by frequency/recency |
| **HTTP Error Series** | Finds HTTP 4xx/5xx spikes correlated with incident window |
| **Kube Crashes** | OOMKills, pod restarts, evictions in K8s |
| **Log Query** | Custom LogQL query results correlated to incident time |
| **Metric Query** | Custom PromQL anomalies around incident window |
| **Noisy Neighbors** | Detects resource contention from co-located services |
| **Recent Deployments** | Correlates recent Helm/K8s deployments with incident start |
| **Resource Contention** | CPU throttling, memory pressure, disk I/O saturation |

## Trigger points

- Explore → "Run Sift Investigation"
- Dashboard panel → "Investigate with Sift"
- Grafana Incident → "Run Sift" button
- Command palette (`Cmd+K`) → "Start Sift investigation"
- OnCall escalation chains → automatic trigger

## API trigger

```bash
curl -X POST https://<stack>.grafana.net/api/plugins/grafana-sift-app/resources/sift/v1/investigations \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "checkout-latency-spike",
    "start": "2024-02-01T10:00:00Z",
    "end":   "2024-02-01T10:30:00Z",
    "filters": { "service": "checkout", "namespace": "production" }
  }'
```
