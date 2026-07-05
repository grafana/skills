# Azure Private Link + GCP Private Service Connect

## Azure Private Link

**Prereq:** Pre-register your Subscription IDs with Grafana Support before starting.

### Portal

1. Private Endpoints → Create
2. Resource tab → "Connect to Azure resource by resource ID or alias"
3. Paste Service Alias from Grafana Cloud → Stack Details
4. Select your VNet and subnet
5. Wait for automatic approval (~10 minutes)

### Azure CLI

```bash
az network private-endpoint create \
  --name grafana-metrics-endpoint \
  --resource-group myRG \
  --vnet-name myVNet \
  --subnet mySubnet \
  --connection-name grafana-metrics \
  --private-connection-resource-id "<service-alias-from-grafana-cloud>" \
  --group-ids grafana-metrics
```

### Verification

```bash
# Confirm endpoint state is "Approved"
az network private-endpoint show \
  --name grafana-metrics-endpoint \
  --resource-group myRG \
  --query 'privateLinkServiceConnections[0].privateLinkServiceConnectionState.status'

# DNS resolution should yield a private IP
nslookup prometheus-private.eu-west-2.grafana.net
```

## GCP Private Service Connect

```bash
gcloud compute forwarding-rules create grafana-metrics-psc \
  --region=us-east1 \
  --network=my-vpc \
  --subnet=my-subnet \
  --address=grafana-metrics-ip \
  --target-service-attachment=projects/grafana-cloud/regions/us-east1/serviceAttachments/metrics
```

### Verification

```bash
# Confirm forwarding rule is "ACCEPTED"
gcloud compute forwarding-rules describe grafana-metrics-psc --region=us-east1 \
  --format='value(pscConnectionStatus)'

# DNS check
nslookup prometheus-private.us-east-0.grafana.net
```

## Private Data Source Connect (PDC)

Different product — for the reverse direction (Grafana Cloud pulling FROM your private network for data-source queries, not your telemetry pushing TO Grafana Cloud).

```bash
helm install pdc grafana/grafana-agent \
  --version 0.44.2 \
  --set pdcConfig.hostedGrafanaId=<your-stack-id> \
  --set pdcConfig.token=<pdc-token>
```

PDC creates an encrypted tunnel from Grafana Cloud back into your private network.
