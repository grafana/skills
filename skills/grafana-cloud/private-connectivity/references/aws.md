# AWS PrivateLink — full setup

Same-region only. For cross-region, set up VPC peering first.

## AWS CLI

```bash
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-12345 \
  --service-name com.amazonaws.vpce.us-east-1.vpce-svc-0abc123 \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-12345 \
  --security-group-ids sg-12345 \
  --private-dns-enabled
```

## Terraform

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

Repeat per signal type (metrics / logs / traces / profiles).

## Verification

```bash
# Confirm endpoint is "available"
aws ec2 describe-vpc-endpoints --vpc-endpoint-ids vpce-xxxxxx

# Confirm private DNS resolves to a private IP
dig +short prometheus-private.us-east-0.grafana.net
# Should resolve to 10.x.x.x (private), not a public IP
```

If DNS still resolves public, check `private_dns_enabled = true` was set and the VPC has DNS resolution + DNS hostnames enabled.
