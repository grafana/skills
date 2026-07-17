# Cost Impact Analysis

Fill the report's **Cost Impact Analysis** section from measured Grafana Cloud usage metrics. Percentages below are illustrative — replace with measured values and the contract per-GB rate.

## Report formatting rules (investigation UI)

Investigation reports render wide markdown tables and panel JSON poorly. When writing Cost Impact Analysis:

1. **Use the scenario-card shape below** — prose opener, bullet baseline, then A/B/C cards. Do **not** paste a markdown table into the customer report.
2. **Never dump panel/query JSON** (`panelId`, `targets`, `datasource` blocks). Cite measured values inline; optionally add a short panel ID or PromQL in parentheses (e.g. `~3,686 active streams (p23)`). Sources already carry query detail.
3. **Open with the dual-path billing note** — labels affect streams/index/query; billable $ follows ingest volume only.

## How label changes translate to billing

Label cardinality changes (removing high-churn labels such as `pod`, raw `filename`, optionally `node`, plus duplicate/constant labels) do not reduce ingested bytes directly. Loki bills on compressed bytes ingested, not on stream count. Do **not** treat `instance` as a default removal — it is acceptable for fixed Host/VM infrastructure when it matches access patterns. What high-cardinality labels _do_ inflate is:

* **Index storage** — each unique label combination creates a TSDB index entry; more streams = larger index = higher memory and storage overhead
* **Query compute** — scanning across thousands of streams is slower and consumes more Querier CPU

The billing-visible savings come from changes that label cleanup _enables_:

1. Normalize `level` first — once `level` has 5 stable lowercase values, a `stage.drop` in Alloy can discard `debug` and `trace` streams before ingest. Debug/trace often accounts for 20–40% of volume in verbose K8s workloads. **Guardrail:** only recommend dropping debug/trace after explicit customer confirmation; prefer env scoping (e.g. drop only when `env=prod`) or sampling rather than a blanket drop.
2. Log-line optimization — removing embedded timestamps, ANSI color codes, null/empty JSON fields, and duplicate level fields. Observed savings are typically 15–38%; the 38% figure is from the Istio example in [log-line-optimization.md](log-line-optimization.md), not a universal expectation.

## Required report shape (paste and fill)

Use this exact section structure in the audit report. Replace bracketed placeholders with measured values.

```markdown
### Cost Impact Analysis

**Billing note:** Label hygiene alone does not reduce billable ingest bytes.
Stream count and query cost improve; ingest $ drops only when volume is reduced
(debug/trace drop and/or log-line compaction).

**Measured baseline** (Grafana Cloud usage metrics):
- Active streams: [N]
- Billable ingest: [rate in MB/s or B/s]
- Overage: [units or $] ([stack / instance id if known])
- Top ingest contributor: [name] ([rate]) — omit if unavailable

**Scenario A — Label hygiene only (this audit)**
- Actions: [labels to remove/normalize/consolidate]
- Stream impact: [current → estimated] ([% if known])
- Volume / $ impact: $0 direct ingest savings
- Overage: unchanged when overage is ingest-driven
- Indirect value: smaller index, lower memory pressure, fewer query timeouts / stream-limit risks

**Scenario B — A + approved debug/trace drop**
- Actions: normalize `level`, then `stage.drop` for debug/trace (**customer-approved / env-scoped only**)
- Volume impact: [measured debug/trace share, or ~15–30% illustrative]
- $ / overage: [estimate from contract $/GB, or qualitative if rate unknown]
- Guardrail: do not recommend a blanket drop without confirmation

**Scenario C — B + log-line compaction**
- Actions: strip ANSI, null/empty JSON fields, redundant timestamps; focus top contributors
- Volume impact: [additional %; Istio example ceiling ~38% total with B is not universal]
- Highest-value target: [top contributor and rate]

**Attribution gap:** [configured attribution label(s), unlabeled/`__missing__` share, or "not enabled"]
**Caveats:** [which % are still illustrative; $/GB unknown; drop scoping]
```

### Agent-only scenario reference (do not paste as a table)

| Scenario | Actions | Streams | Volume | Direct $ | Overage |
|---|---|---|---|---|---|
| A | Label hygiene | Large drop (often −65 to −90%) | 0% | $0 | Unchanged |
| B | A + approved level drop | Similar to A | Often ~−15 to −30% | % of bill × volume cut | Often reduced |
| C | B + line compaction | Similar to A | Additional ~5–15% (workload-dependent) | Larger than B | Often eliminated when measured |

Apply contract per-GB rate: `monthly_GB × reduction_%` (where `monthly_GB = bytes_per_second × 86400 × 30 / 1e9`).

## Cost attribution prerequisite

Grafana Cloud cost attribution uses **customer-configured** attribution label(s) (often `team`, `service`, or `env` — check Cost Management → Settings; up to two labels). Soft-enforce whichever label is configured (see Soft Enforcement in the skill body), not a hard-coded `owner`.

Check unattributed volume (substitute the configured label for `<attr_label>`; `__missing__` only appears when attribution is enabled):

```PromQL
sum by (<attr_label>) (grafanacloud_logs_instance_attributed_bytes_received_per_second)
```

A high `__missing__` (or unlabeled) share means most overage cannot be assigned to a team. Soft-enforce the configured label with `stage.template` to inject `unknown` when absent, then work with teams to populate it correctly.

## Measuring baseline before and after

Query these against the **Grafana Cloud billing/usage metrics** datasource before changes, then again ~7 days after deploying the Alloy pipeline. Report **scalar results**, not the query JSON:

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
