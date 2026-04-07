---
name: loki
license: Apache-2.0
description: >
  Grafana Loki log aggregation overview including LogQL query language, Logs Drilldown, structured metadata,
  and integration patterns. Use when working with Loki, writing LogQL queries, configuring log pipelines,
  or discussing log aggregation architecture and best practices.
---

# Log Aggregation with Grafana Loki

## Value Proposition

Horizontally scalable, multi-tenant log aggregation system inspired by Prometheus. Indexes only metadata (labels)
rather than full-text, dramatically reducing storage costs while maintaining powerful querying through LogQL.

**Key Differentiators**: Index-free architecture (labels only), Prometheus label conventions, multi-tenancy,
LogQL query language, excellent compression (10x+ reduction).

## LogQL Quick Reference

### Log Stream Selection

```logql
# Single label match
{job="nginx"}

# Multiple labels (AND)
{job="nginx", env="prod"}

# Regex match
{job=~"nginx|apache"}

# Negative match
{job!="debug"}
```

### Line Filters

```logql
# Contains substring
{job="nginx"} |= "error"

# Does not contain
{job="nginx"} != "info"

# Regex match
{job="nginx"} |~ "error|warn"

# Case-insensitive
{job="nginx"} |~ "(?i)error"
```

### Parser Expressions

```logql
# JSON parsing
{job="api"} | json | status >= 500

# Logfmt parsing
{job="api"} | logfmt | level="error"

# Regex extraction
{job="api"} | regexp `(?P<ip>\d+\.\d+\.\d+\.\d+)`

# Pattern matching
{job="nginx"} | pattern `<ip> - - <_> "<method> <path> <_>" <status>`
```

### Metric Queries (from logs)

```logql
# Rate of log lines per second
rate({job="nginx"}[5m])

# Count over time
count_over_time({job="nginx"} |= "error" [5m])

# Sum of extracted values
sum by (status) (rate({job="api"} | json | __error__="" [5m]))

# Bytes rate
bytes_rate({job="nginx"}[5m])

# Quantile of extracted values
quantile_over_time(0.99, {job="api"} | json | unwrap response_time [5m])
```

## Logs Drilldown

Queryless log exploration app for Loki (requires Loki v3.2+):
- Find logs and volumes for all services without writing LogQL
- Filter by labels, fields, or patterns
- Volume and text pattern analysis
- Automatic log level detection (INFO, WARN, ERROR)

## Architecture

- **Distributor**: Accepts log entries, validates, routes to ingesters
- **Ingester**: Builds compressed chunks in memory, flushes to object storage
- **Querier**: Queries ingesters + object storage
- **Object storage**: S3, GCS, Azure Blob, or local filesystem
- **Compression**: Snappy/gzip for excellent storage efficiency

## Integration and Enrichment

- **Grafana Alloy**: Unified telemetry collection with advanced pipelines
- **Label enrichment**: Automatic K8s metadata, EC2 tags
- **Structured metadata**: High-cardinality data without indexing overhead
- **Derived fields**: Extract trace IDs, span IDs for correlation with Tempo

## Resources

- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [LogQL Reference](https://grafana.com/docs/loki/latest/query/)
- [Logs Drilldown App](https://github.com/grafana/logs-drilldown)
- [Grafana Alloy](https://grafana.com/docs/alloy/)
