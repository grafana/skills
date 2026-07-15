# Cost Impact Analysis

Fill the report's **Cost Impact Analysis** section from measured Grafana Cloud usage metrics. Percentages below are illustrative — replace with measured values and the contract per-GB rate.

## How label changes translate to billing

Label cardinality changes (removing high-churn labels such as `pod`, raw `filename`, optionally `node`, plus duplicate/constant labels) do not reduce ingested bytes directly. Loki bills on compressed bytes ingested, not on stream count. Do **not** treat `instance` as a default removal — it is acceptable for fixed Host/VM infrastructure when it matches access patterns. What high-cardinality labels _do_ inflate is:

* **Index storage** — each unique label combination creates a TSDB index entry; more streams = larger index = higher memory and storage overhead
* **Query compute** — scanning across thousands of streams is slower and consumes more Querier CPU

The billing-visible savings come from changes that label cleanup _enables_:

1. Normalize `level` first — once `level` has 5 stable lowercase values, a `stage.drop` in Alloy can discard `debug` and `trace` streams before ingest. Debug/trace often accounts for 20–40% of volume in verbose K8s workloads. **Guardrail:** only recommend dropping debug/trace after explicit customer confirmation; prefer env scoping (e.g. drop only when `env=prod`) or sampling rather than a blanket drop.
2. Log-line optimization — removing embedded timestamps, ANSI color codes, null/empty JSON fields, and duplicate level fields. Observed savings are typically 15–38%; the 38% figure is from the Istio example in [log-line-optimization.md](log-line-optimization.md), not a universal expectation.

## Savings scenarios

Replace illustrative percentages with measured values from the Grafana Cloud usage metrics datasource (not the customer's Loki datasource) using `grafanacloud_logs_instance_billable_bytes_received_per_second` and `grafanacloud_org_logs_overage`, then apply the contract per-GB rate.

| Scenario | Actions | Stream reduction | Volume reduction | Est. monthly savings¹ | Overage impact |
|---|---|---|---|---|---|
| A — Label hygiene only | Remove high-churn K8s labels (`pod`, raw `filename`, optionally `node`); drop duplicate + constant labels | ~−65 to −75% (illustrative) | 0% | $0 direct² | None |
| B — Level fix + debug/trace drop | Scenario A + normalize level + `stage.drop` for debug/trace (**only if customer-approved / env-scoped**) | ~−75% (illustrative) | ~−25% (illustrative) | ~25% of monthly bill (replace with measured) | Often reduced or eliminated |
| C — Full optimization | Scenario B + log-line cleanup (timestamps, nulls, ANSI) | ~−80% (illustrative) | ~−38% (Istio example ceiling) | ~volume reduction % of monthly bill | Eliminated + net savings (when measured) |

¹ Apply contract per-GB rate to `monthly_volume_GB × reduction_%` for a dollar figure.
² Scenario A produces **indirect** value: smaller index, lower Loki memory pressure, reduced query timeout risk, and avoidance of stream-count ingestion throttling limits.

## Cost attribution prerequisite

Grafana Cloud cost attribution uses **customer-configured** attribution label(s) (often `team`, `service`, or `env` — check Cost Management → Settings; up to two labels). Soft-enforce whichever label is configured (see Soft Enforcement in the skill body), not a hard-coded `owner`.

Check unattributed volume (substitute the configured label for `<attr_label>`; `__missing__` only appears when attribution is enabled):

```PromQL
sum by (<attr_label>) (grafanacloud_logs_instance_attributed_bytes_received_per_second)
```

A high `__missing__` (or unlabeled) share means most overage cannot be assigned to a team. Soft-enforce the configured label with `stage.template` to inject `unknown` when absent, then work with teams to populate it correctly.

## Measuring baseline before and after

Query these against the **Grafana Cloud billing/usage metrics** datasource before changes, then again ~7 days after deploying the Alloy pipeline:

```PromQL
# Billable ingestion rate (bytes/s)
grafanacloud_logs_instance_billable_bytes_received_per_second

# Active stream count
grafanacloud_logs_instance_active_streams

# Current period monetary overage
grafanacloud_org_logs_overage{monetary="true"}

# Volume by configured attribution label (identifies unattributed share)
sum by (<attr_label>) (grafanacloud_logs_instance_attributed_bytes_received_per_second)
```

Convert the ingestion rate to a monthly volume equivalent:

```
monthly_GB = bytes_per_second × 86400 × 30 / 1e9
```
