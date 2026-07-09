---
name: database-observability
license: Apache-2.0
description: Set up Grafana Cloud Database Observability for MySQL and PostgreSQL — enables `pg_stat_statements` / Performance Schema, creates a least-privilege monitoring user, configures the `database_observability.postgres` / `database_observability.mysql` Alloy components, ships query samples + visual explain plans + RED metrics + schema details to Grafana Cloud, and correlates slow queries with application traces via `db.statement` / `db.system` OTel attributes. Use when monitoring database performance, diagnosing slow queries, setting up DB observability for RDS / Aurora / Cloud SQL / Azure Database / self-managed instances, correlating DB metrics with APM, or alerting on query latency — even when the user says "my database is slow", "find the slow queries", or "monitor RDS" without saying "observability".
---

# Grafana Cloud Database Observability

> **Docs**: https://grafana.com/docs/grafana-cloud/monitor-applications/database-observability/

Query-level insights (RED metrics, query samples, explain plans) for MySQL and PostgreSQL without application code changes. GA since April 2026.

## Common Workflows

### PostgreSQL setup

```sql
-- 1. Enable pg_stat_statements (requires restart)
--    In postgresql.conf:  shared_preload_libraries = 'pg_stat_statements'
--    Then restart PostgreSQL.

-- 2. Create a least-privilege monitoring user
CREATE USER grafana_monitoring WITH PASSWORD 'secret';
GRANT pg_monitor TO grafana_monitoring;
GRANT CONNECT ON DATABASE mydb TO grafana_monitoring;

-- 3. Enable the extension on each monitored DB
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- 4. Verify
SELECT count(*) FROM pg_stat_statements;
-- Should return >= 0 (not an error). If "relation does not exist": step 3 didn't run.
```

5. Add the [Alloy config block from references/alloy-config.md § PostgreSQL](references/alloy-config.md#postgresql)
6. Restart Alloy and wait ~60s for first scrape
7. **Verify in Grafana Cloud** → Database Observability — the instance should appear with non-empty `db_query_total{db_instance="mydb"}` series. If empty after 2 minutes: check Alloy logs for connection errors, then re-verify pg_stat_statements permissions.

### MySQL setup

```sql
-- 1. Create least-privilege monitoring user
CREATE USER 'grafana_monitoring'@'%' IDENTIFIED BY 'secret';
GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO 'grafana_monitoring'@'%';
GRANT SELECT ON performance_schema.* TO 'grafana_monitoring'@'%';
FLUSH PRIVILEGES;

-- 2. Verify performance_schema is enabled (default in MySQL 8+)
SELECT @@performance_schema;
-- Returns 1 → enabled. 0 → set performance_schema=ON in my.cnf + restart.
```

3. Add the [Alloy config block from references/alloy-config.md § MySQL](references/alloy-config.md#mysql)
4. Restart Alloy, wait ~60s, verify the instance appears in Grafana Cloud → Database Observability

## Supported databases

| Database | Variants |
|----------|---------|
| **MySQL** | Self-managed, RDS MySQL, Aurora MySQL, Cloud SQL MySQL, Azure Database for MySQL |
| **PostgreSQL** | Self-managed, RDS PostgreSQL, Aurora PostgreSQL, Cloud SQL PostgreSQL, Azure Database for PostgreSQL |

For managed databases (RDS / Cloud SQL / Azure), `pg_stat_statements` is preinstalled but disabled — enable it via the parameter group / flag, then re-create the extension at the DB level.

## What you get

- **Query Performance dashboard** (auto-provisioned): top queries by total time / call count / mean latency, sampled query texts with parameters, visual explain plans, RED metrics per query digest
- **APM correlation**: drill from a slow service-latency span to the specific slow SQL via `db.statement` / `db.system` / `db.name` OTel attributes — see [references/queries-alerts.md § Trace correlation](references/queries-alerts.md#trace-correlation)
- **Alerting** on query latency, error rate, and connection-pool saturation — full alert YAML in [references/queries-alerts.md § Alert rules](references/queries-alerts.md#alert-rules)

## References

- [`references/alloy-config.md`](references/alloy-config.md) — full Alloy `database_observability.postgres` / `database_observability.mysql` config blocks + collector reference (`pg_stat_statements`, `query_samples`, `schema_details`, `explain_plans`)
- [`references/queries-alerts.md`](references/queries-alerts.md) — key PromQL queries, alert rule YAML, and trace-correlation setup
