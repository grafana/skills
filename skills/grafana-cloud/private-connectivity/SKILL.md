---
name: private-connectivity
license: Apache-2.0
description: Set up private network connectivity to Grafana Cloud — AWS PrivateLink, Azure Private Link, GCP Private Service Connect, and Private Data Source Connect (PDC). Provisions VPC endpoints, private endpoints, or PSC forwarding rules per signal type (metrics / logs / traces / profiles); wires Alloy to push to the private DNS endpoint instead of the public one; verifies private DNS resolution + endpoint approval state. Use when sending telemetry to Grafana Cloud without traversing the public internet, eliminating cloud egress costs, meeting PCI-DSS / HIPAA / data-residency compliance, configuring PDC for private data-source queries, or connecting AWS / Azure / GCP workloads to Grafana — even when the user says "stop paying egress", "keep our telemetry off the public internet", or "PCI compliance for Grafana" without naming PrivateLink.
---

# Grafana Cloud Private Connectivity

> **Docs**: https://grafana.com/docs/grafana-cloud/send-data/

Send metrics, logs, traces, and profiles to Grafana Cloud entirely over your cloud provider's private backbone — no public internet exposure, no egress fees.

## Common Workflows

### Setting up AWS PrivateLink (most common)

1. **Find your service names.** Grafana Cloud → Stack Details → "Send using AWS PrivateLink". Note one service name per signal type (metrics / logs / traces / profiles).

2. **Create an Interface VPC Endpoint per signal type:**

   ```bash
   aws ec2 create-vpc-endpoint \
     --vpc-id vpc-12345 \
     --service-name com.amazonaws.vpce.us-east-1.vpce-svc-0abc123 \
     --vpc-endpoint-type Interface \
     --subnet-ids subnet-12345 \
     --security-group-ids sg-12345 \
     --private-dns-enabled
   ```

3. **Verify private DNS resolves** (CRITICAL — if this returns a public IP, Alloy will silently keep using the public path and you'll keep paying egress):

   ```bash
   dig +short prometheus-private.us-east-0.grafana.net
   # Expected: a 10.x.x.x / 172.16-31.x.x / 192.168.x.x address
   # Public IP returned → check `private_dns_enabled = true` was set and the VPC has DNS hostnames enabled
   ```

4. **Update Alloy to use the private endpoint:**

   ```alloy
   prometheus.remote_write "cloud_private" {
     endpoint {
       url = "https://prometheus-private.us-east-0.grafana.net/api/prom/push"
       basic_auth {
         username = sys.env("PROM_USER")
         password = sys.env("GRAFANA_CLOUD_API_KEY")
       }
     }
   }

   loki.write "cloud_private" {
     endpoint {
       url = "https://logs-private.us-east-0.grafana.net/loki/api/v1/push"
       basic_auth {
         username = sys.env("LOKI_USER")
         password = sys.env("GRAFANA_CLOUD_API_KEY")
       }
     }
   }
   ```

5. **Confirm traffic is flowing over PrivateLink:** check the VPC endpoint's CloudWatch metrics for `BytesProcessed` after Alloy starts pushing.

Full Terraform + per-signal-type endpoint resources in [references/aws.md](references/aws.md).

### Setting up Azure Private Link / GCP Private Service Connect

Different provider, same shape: create the private endpoint → wait for approval → verify private DNS → update Alloy URLs. Full CLI + verification steps in [references/azure-gcp.md](references/azure-gcp.md).

**Azure-specific prereq:** Pre-register your Subscription IDs with Grafana Support before starting — without this the endpoint creation hangs at "Pending".

## Prerequisites (all providers)

- Grafana Cloud stack must be hosted on the same cloud provider (check: My Account → Stack → Details)
- Create separate private endpoints for each signal type (metrics / logs / traces / profiles) — they have distinct service names
- Same region only for AWS PrivateLink. Cross-region requires VPC peering first.

## Choosing the right option

| Scenario | Solution |
|----------|----------|
| Push from AWS | AWS PrivateLink |
| Push from Azure | Azure Private Link |
| Push from GCP | GCP Private Service Connect |
| Query private DB / Prometheus from Grafana | Private Data Source Connect (PDC) — see [references/azure-gcp.md § PDC](references/azure-gcp.md#private-data-source-connect-pdc) |

## References

- [`references/aws.md`](references/aws.md) — full AWS PrivateLink Terraform per signal type + endpoint verification (state + DNS)
- [`references/azure-gcp.md`](references/azure-gcp.md) — Azure Private Link + GCP Private Service Connect setup (Portal + CLI) + verification + Private Data Source Connect (PDC) for reverse-direction private data source queries
