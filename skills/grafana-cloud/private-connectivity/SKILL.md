---
name: private-connectivity
license: Apache-2.0
description: >
  Grafana Cloud private network connectivity — AWS PrivateLink, Azure Private Link, and GCP Private
  Service Connect. Send telemetry (metrics, logs, traces, profiles) to Grafana Cloud without traversing
  the public internet. Eliminates cloud egress costs, meets compliance requirements (PCI-DSS, HIPAA).
  Use when setting up secure private telemetry ingestion from AWS/Azure/GCP, reducing egress costs,
  or meeting data residency/compliance requirements.
---

# Grafana Cloud Private Connectivity

> **Docs**: https://grafana.com/docs/grafana-cloud/send-data/

Send metrics, logs, traces, and profiles to Grafana Cloud entirely over your cloud provider's
private backbone — no public internet exposure, no egress fees.

## Prerequisites

**All providers:**
- Grafana Cloud stack must be hosted on the same cloud provider (check: My Account → Stack → Details)
- Create separate private endpoints for each signal type (Metrics, Logs, Traces, Profiles)

## AWS PrivateLink

### Setup

1. **Get Service Names** from Grafana Cloud → Stack Details → "Send using AWS PrivateLink"
2. **Create Interface VPC Endpoints** in AWS Console for each service:

```bash
# Via AWS CLI
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-12345 \
  --service-name com.amazonaws.vpce.us-east-1.vpce-svc-0abc123 \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-12345 \
  --security-group-ids sg-12345 \
  --private-dns-enabled
```

3. **Update Alloy config** to use private DNS names from Grafana Cloud console:

```alloy
prometheus.remote_write "cloud_private" {
  endpoint {
    // Use private DNS name instead of public endpoint
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

### Terraform

```hcl
resource "aws_vpc_endpoint" "grafana_metrics" {
  vpc_id              = var.vpc_id
  service_name        = var.grafana_metrics_service_name  # from Grafana Cloud console
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.grafana_endpoint.id]
  private_dns_enabled = true

  tags = { Name = "grafana-metrics-privatelink" }
}

resource "aws_vpc_endpoint" "grafana_logs" {
  vpc_id              = var.vpc_id
  service_name        = var.grafana_logs_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.grafana_endpoint.id]
  private_dns_enabled = true

  tags = { Name = "grafana-logs-privatelink" }
}
```

**Limitation:** PrivateLink only works within the same AWS region. For cross-region, set up VPC peering first.

## Azure Private Link

### Setup

1. **Get Service Alias** from Grafana Cloud → Stack Details (one per signal type)
2. **Create Private Endpoint** in Azure Portal:
   - Private Endpoints → Create
   - Resource tab → "Connect to Azure resource by resource ID or alias"
   - Paste Service Alias from Grafana Cloud
   - Select your VNet and subnet
3. Wait for automatic approval (~10 minutes)

```bash
# Via Azure CLI
az network private-endpoint create \
  --name grafana-metrics-endpoint \
  --resource-group myRG \
  --vnet-name myVNet \
  --subnet mySubnet \
  --connection-name grafana-metrics \
  --private-connection-resource-id "<service-alias-from-grafana-cloud>" \
  --group-ids grafana-metrics
```

**Note:** Azure Private Link requires pre-registering your Subscription IDs with Grafana Support before setup.

## GCP Private Service Connect

1. **Get service attachment URI** from Grafana Cloud console
2. **Create Private Service Connect endpoint** in GCP:

```bash
gcloud compute forwarding-rules create grafana-metrics-psc \
  --region=us-east1 \
  --network=my-vpc \
  --subnet=my-subnet \
  --address=grafana-metrics-ip \
  --target-service-attachment=projects/grafana-cloud/regions/us-east1/serviceAttachments/metrics
```

## Private Data Source Connect (PDC)

For connecting to **data sources** (databases, Prometheus, etc.) hosted in private networks, use PDC — a separate product from private telemetry ingestion:

```bash
# Install PDC agent
helm install pdc grafana/grafana-agent \
  --set pdcConfig.hostedGrafanaId=<your-stack-id> \
  --set pdcConfig.token=<pdc-token>
```

PDC creates an encrypted tunnel from Grafana Cloud back into your private network for data source queries. It's the reverse direction of PrivateLink (pull vs push).

## Choosing the Right Option

| Scenario | Solution |
|----------|----------|
| Push metrics/logs/traces from AWS | AWS PrivateLink |
| Push metrics/logs/traces from Azure | Azure Private Link |
| Push metrics/logs/traces from GCP | GCP Private Service Connect |
| Query private DB/Prometheus from Grafana | Private Data Source Connect (PDC) |
| On-premises with no cloud provider | Grafana Agent with TLS over internet |

## Cost Savings

AWS PrivateLink eliminates:
- **$0.09/GB** cross-region data transfer (typical Grafana Cloud endpoint is in same region)
- **$0.09/GB** internet data transfer fees
- Potential NAT Gateway costs

At 100GB/month of telemetry: ~$9-18/month savings per endpoint type.
