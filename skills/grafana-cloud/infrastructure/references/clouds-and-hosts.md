# Cloud-provider + host / container collection

## AWS CloudWatch

Scrape via the CloudWatch exporter:

```alloy
prometheus.scrape "cloudwatch" {
  targets    = [{__address__ = "cloudwatch-exporter:9106"}]
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
      authType: default          # uses EC2 instance / ECS task role
      # Or explicit creds:
      # authType: credentials
    secureJsonData:
      accessKey: AKIAIOSFODNN7EXAMPLE
      secretKey: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

## Azure Monitor

```yaml
# provisioning/datasources/azure.yaml
apiVersion: 1
datasources:
  - name: Azure Monitor
    type: grafana-azure-monitor-datasource
    jsonData:
      cloudName: AzureCloud
      tenantId:  your-tenant-id
      clientId:  your-client-id
    secureJsonData:
      clientSecret: your-client-secret
```

## Google Cloud Monitoring

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

## Node Exporter (Linux host) via Alloy

```alloy
prometheus.exporter.unix "host" {
  rootfs_path = "/"
  enable_collectors = ["cpu", "diskstats", "filesystem", "loadavg", "meminfo", "netdev", "stat", "time", "uname"]
}

prometheus.scrape "node" {
  targets         = prometheus.exporter.unix.host.targets
  forward_to      = [prometheus.remote_write.cloud.receiver]
  scrape_interval = "60s"
}
```

## Docker / cAdvisor via Alloy

```alloy
prometheus.scrape "cadvisor" {
  targets      = [{"__address__" = "localhost:8080"}]
  metrics_path = "/metrics"
  forward_to   = [prometheus.remote_write.cloud.receiver]
}

discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

loki.source.docker "containers" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.docker.containers.targets
  forward_to = [loki.write.cloud.receiver]
}
```
