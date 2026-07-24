# Protected / Correlation Labels

Hard never-drop allowlist for Grafana Cloud cross-signal correlation and Application Observability. Load this when evaluating any label for demotion or when writing `stage.label_keep` lists.

## Allowlist (never drop the key)

| Label | Source / notes |
|---|---|
| `service_name` | OTel `service.name` — joins logs, traces, metrics, service inventory, traces-to-logs |
| `deployment_environment` | OTel `deployment.environment` — environment scoping in App O11y |
| `job` | Often `service.namespace`/`service.name` — present on span metrics and many dashboards |

If any of these keys exist on a stream, **keep them**. Cardinality problems on protected keys are **value** problems, not key problems.

## Why dropping breaks things

Grafana Cloud features and customer-owned artifacts select on these labels:

- Application Observability service inventory and Logs panels (join on `service_name` / `service.name`)
- Traces-to-logs and metrics-to-logs correlation
- Alerts, dashboards, recording rules, and LBAC policies that already use these selectors

Hard-dropping a protected key (or omitting it from `label_keep`) can silently break correlation and production selectors even when stream count improves.

## Remediate values, not keys

When a protected label has high cardinality (UUID `service_name`, short-lived job names, ephemeral environment strings):

1. **Keep the label key**
2. **Stabilize values** at collect time — map UUID / ephemeral names to a durable service identity (service catalog name, workload name, or OTel `service.name`)
3. **Document the mapping** in Migration Notes so alerts and dashboards stay aligned
4. Never recommend “remove `service_name`” (or peers) to fix cardinality

Example audit action: `service_name` values look like UUIDs → Keep key | Normalize values to stable service identity (do not drop label).

## Aliases (`app` / `service`)

Prefer `service_name` for Grafana Cloud / OTel alignment. If the tenant only has `app` or `service`:

- **Add or align** `service_name` to match OTel `service.name` across signals
- Do **not** delete `app` / `service` without an explicit migration plan for existing selectors
- Treat aliases as transitional, not as replacements for the allowlist

## Downstream dependency guardrail

Before recommending demotion or rename of **any** label (protected or not):

- Call out alerts, dashboards, LBAC, and recording rules that may select on it
- Require a Migration Notes plan (dual-write / add-then-cutover / update selectors)
- Ask the user to confirm known dependencies when they are unknown — do not invent a clean cutover
