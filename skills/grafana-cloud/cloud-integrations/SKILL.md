---
name: cloud-integrations
license: Apache-2.0
description:
  Set up, configure, and troubleshoot Grafana Cloud integrations for AWS, Azure, and other cloud
  providers. Use when the user asks to connect AWS CloudWatch, set up Azure Monitor, configure
  Confluent Cloud observability, install a Grafana integration, set up hosted exporters, use
  AWS Firehose for CloudWatch logs, or troubleshoot a cloud integration. Triggers on phrases
  like "AWS CloudWatch", "Azure Monitor", "Confluent integration", "cloud integration",
  "hosted exporter", "AWS Firehose", "install integration", "cloud metrics", or "cloud logs".
---

# Grafana Cloud Integrations

Grafana Cloud Integrations connect cloud provider monitoring APIs to your Grafana stack without
running your own exporters. Hosted exporters scrape cloud APIs on your behalf and push metrics
to your Grafana Cloud stack.

**Supported hosted exporters:**
- **AWS CloudWatch** - all CloudWatch namespaces via YACE (Yet Another CloudWatch Exporter)
- **Azure Monitor** - Azure resource metrics via the Azure Monitor API
- **Confluent Cloud** - Kafka cluster metrics via the Confluent Metrics API
- **Generic HTTP endpoint** - any Prometheus-format `/metrics` endpoint behind auth

**AWS Firehose receiver** - ingests CloudWatch Logs and Metrics Streams pushed via Kinesis
Firehose (near real-time, lower latency than API scraping).

---

## Step 1: Navigate to Connections

In Grafana Cloud: **Connections > Add new connection** (or `Connections > Cloud Provider`).

Available paths:
- **AWS CloudWatch** - hosted exporter + optional Firehose receiver
- **Azure Monitor** - hosted exporter
- **Confluent Cloud** - hosted exporter
- **All integrations** - full catalog including Linux, MySQL, Kubernetes, etc.

---

## Step 2: AWS CloudWatch integration

### Option A: Hosted exporter (polling)

The hosted exporter scrapes CloudWatch API every 60s. Latency: ~1-5 minutes.

**Required IAM permissions (minimum):**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "tag:GetResources",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions"
      ],
      "Resource": "*"
    }
  ]
}
```

**Setup steps:**
1. Create an IAM user or role with the policy above
2. Generate an access key pair (for IAM user) or configure cross-account role assumption
3. In Grafana Cloud: Connections > AWS > Configure hosted exporter
4. Enter: AWS Access Key ID, Secret Access Key, region(s), CloudWatch namespaces to scrape
5. Grafana provisions the exporter and begins scraping within 2-3 minutes

**Supported namespaces:** EC2, RDS, ELB/ALB, S3, Lambda, ECS, SQS, SNS, ElastiCache,
Kinesis, DynamoDB, and 50+ others.

### Option B: AWS Firehose receiver (streaming)

Near-real-time metrics and logs via CloudWatch Metric Streams and CloudWatch Logs subscriptions.

**Architecture:**
```
CloudWatch Metric Streams → Kinesis Firehose → Grafana Cloud Firehose Receiver
CloudWatch Logs (subscription filter) → Kinesis Firehose → Grafana Cloud Firehose Receiver
```

**Setup:**

1. In Grafana Cloud: Connections > AWS > Firehose receiver
2. Grafana provides an HTTPS endpoint URL and access token
3. In AWS, create a Kinesis Firehose delivery stream:
   - Destination: HTTP endpoint
   - Endpoint URL: (from step 2)
   - Access key: (from step 2)
   - Content encoding: GZIP
4. Create a CloudWatch Metric Stream pointing at the Firehose stream:
   - Output format: `OpenTelemetry 1.0`
   - Namespaces: select or include all
5. For logs: add a CloudWatch Logs subscription filter pointing at the Firehose stream

**Terraform for Firehose setup:**

```hcl
resource "aws_cloudwatch_metric_stream" "grafana_cloud" {
  name          = "grafana-cloud-metrics"
  role_arn      = aws_iam_role.firehose_role.arn
  firehose_arn  = aws_kinesis_firehose_delivery_stream.grafana.arn
  output_format = "opentelemetry1.0"

  # Optionally scope to specific namespaces
  # include_filter { namespace = "AWS/EC2" }
  # include_filter { namespace = "AWS/RDS" }
}

resource "aws_kinesis_firehose_delivery_stream" "grafana" {
  name        = "grafana-cloud-stream"
  destination = "http_endpoint"

  http_endpoint_configuration {
    url            = var.grafana_firehose_endpoint
    access_key     = var.grafana_firehose_access_key
    name           = "Grafana Cloud"
    content_encoding = "GZIP"

    s3_configuration {
      role_arn   = aws_iam_role.firehose_role.arn
      bucket_arn = aws_s3_bucket.firehose_backup.arn
    }
  }
}
```

---

## Step 3: Azure Monitor integration

**Required Azure permissions:**

Create a service principal with the **Monitoring Reader** role on the subscription(s) to monitor.

```bash
# Create service principal
az ad sp create-for-rbac --name grafana-cloud-monitoring \
  --role "Monitoring Reader" \
  --scopes /subscriptions/<SUBSCRIPTION_ID>

# Output: appId (client ID), password (client secret), tenant
```

**Setup in Grafana Cloud:**
1. Connections > Azure > Configure hosted exporter
2. Enter: Tenant ID, Client ID, Client Secret, Subscription IDs
3. Select resource types to monitor (VMs, App Services, AKS, SQL, etc.)
4. The exporter begins scraping within 2-3 minutes

**Supported resource types:** Virtual Machines, App Service Plans, AKS, Azure SQL, CosmosDB,
Storage Accounts, Event Hubs, Service Bus, Application Gateway, and others.

---

## Step 4: Confluent Cloud integration

**Required Confluent API credentials:**

1. In Confluent Cloud: **Environment > API Keys** (or Cloud API Keys for organization-level)
2. Create a **Metrics API key** (not a Kafka API key) with `MetricsViewer` role
3. Note the API Key and Secret

**Setup in Grafana Cloud:**
1. Connections > Confluent > Configure hosted exporter
2. Enter: Confluent API Key, API Secret, Environment ID(s), Cluster ID(s)
3. The exporter scrapes the Confluent Metrics API every 60s

**Available metrics:** Consumer lag, broker request rates, partition counts, replication lag,
active controller count, and cluster-level health metrics.

---

## Step 5: Verify the integration is working

```bash
# Check in Grafana Explore — query for the integration's job label
# For AWS:
{job="integrations/cloudwatch"}

# For Azure:
{job="integrations/azure-monitor"}

# Check metric arrival (replace with your stack's Prometheus endpoint)
curl -s -H "Authorization: Bearer <USER>:<API_KEY>" \
  "https://prometheus-prod-XX-XX-X.grafana.net/api/prom/api/v1/labels" | \
  jq '.data | map(select(startswith("aws_") or startswith("azure_")))'
```

The integration status is also visible in: **Connections > [Integration name] > Status**

**Integration health indicators:**
- `Last successful scrape` - should be within the last 2 minutes
- `Series count` - should be non-zero and stable
- `Error rate` - should be 0%

---

## Step 6: Pre-built dashboards and alerts

Every integration installs a set of pre-configured dashboards and alert rules automatically.

**Find installed dashboards:**
- Dashboards > Browse > folder named after the integration (e.g. "AWS CloudWatch")

**Find installed alert rules:**
- Alerting > Alert rules > filter by datasource or folder

**Modify without losing updates:**
1. Do not edit the provisioned dashboards directly (they may be overwritten on updates)
2. Duplicate the dashboard (Dashboard settings > Save as copy)
3. Edit the copy

---

## Step 7: Troubleshoot integration failures

**Hosted exporter not receiving data:**

```bash
# Check the integration status via Grafana Cloud API
curl -s -H "Authorization: Bearer <STACK_ID>:<API_TOKEN>" \
  "https://integrations-api.grafana.net/api/v1/integrations" | \
  jq '.integrations[] | {name, status, lastScrapeTime, errorMessage}'
```

**Common errors:**

| Error | Cause | Fix |
|---|---|---|
| `AccessDenied` (AWS) | IAM policy missing permissions | Add required actions to the IAM policy |
| `AuthorizationFailed` (Azure) | Service principal missing role | Grant Monitoring Reader on the subscription |
| `401 Unauthorized` (Confluent) | Wrong API credentials | Re-enter credentials; confirm Metrics API key (not Kafka key) |
| `No metrics found` | Wrong namespace/resource type selected | Add the namespace in integration settings |
| `Scrape timeout` | Network restriction | Ensure Grafana Cloud's IPs can reach the cloud provider API |

**AWS-specific: CloudWatch API rate limiting**

CloudWatch GetMetricData has a rate limit. If you have many resources, enable Metric Streams
(Option B) instead of API polling to avoid throttling.

---

## Step 8: Reduce costs with metric filtering

Hosted exporters scrape all metrics by default. Filter to reduce series count and cost.

**AWS - select specific namespaces:**
In integration settings, switch from "All namespaces" to specific ones (e.g. EC2, RDS only).

**AWS - filter by resource tags:**
```yaml
# In exporter configuration, add tag filters
discovery:
  - type: AWS/EC2
    filters:
      - key: Environment
        values: ["production"]
```

**Azure - select specific resource types:**
Only enable the resource types you actually have dashboards for.

**Use Adaptive Metrics to aggregate away unused label dimensions:**
See the `grafana-cloud/adaptive-metrics` skill.

---

## References

- [Grafana Cloud Connections documentation](https://grafana.com/docs/grafana-cloud/monitor-infrastructure/integrations/)
- [AWS CloudWatch integration](https://grafana.com/docs/grafana-cloud/monitor-infrastructure/integrations/integration-reference/integration-cloudwatch/)
- [Azure Monitor integration](https://grafana.com/docs/grafana-cloud/monitor-infrastructure/integrations/integration-reference/integration-azure/)
- [YACE (Yet Another CloudWatch Exporter)](https://github.com/nerdswords/yet-another-cloudwatch-exporter)
- [CloudWatch Metric Streams](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Metric-Streams.html)
