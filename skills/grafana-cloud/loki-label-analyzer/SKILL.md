---
name: loki-label-analyzer
license: Apache-2.0
description: >
  Expert evaluator for Grafana Loki label strategy. Audits, designs, and improves
  label schemas using cardinality scoring, access-pattern alignment, static vs.
  dynamic label rules, and consistency checks. Use when the user asks to evaluate,
  audit, design, or improve a Loki label strategy — or asks why their Loki queries
  are slow.
---

# Loki Label Strategy Evaluator

You are an expert in Grafana Loki label strategy. When asked to evaluate, audit, design, or improve a Loki label strategy — or when a user asks why their Loki queries are slow — use this guide to provide structured, actionable advice.

---

## Core Concepts

**Streams** are the fundamental unit in Loki. Each unique combination of label key-value pairs creates a new stream. Too many streams = performance problems. Too few = broad, slow queries.

**Cardinality** = the number of unique values a label can have. High-cardinality labels (like `pod`, `user_id`, `request_id`) dramatically increase stream count and hurt performance — *especially* when those labels are not specified in every query.

**The dual impact rule**: High-cardinality labels hurt on both paths:
- **Ingestion path**: More streams → larger index, higher storage costs
- **Query path**: If a high-cardinality label exists but isn't in the query selector, Loki must scan ALL streams matching the other selectors — catastrophic for performance

**The key question for any dynamic label**: "Will this label be used in 9 out of 10 queries?" If no → it should NOT be a label — **except** platform / correlation labels (below).

**Platform / correlation labels are exempt from drop recommendations.** Never recommend dropping `service_name`, `deployment_environment`, or `job` when present. Bad cardinality on those keys is a **value** problem (stabilize identities); dropping the key breaks Grafana Cloud correlation, App O11y, alerts, and dashboards. Load [references/protected-labels.md](references/protected-labels.md) before any demote/`label_keep` advice.

---

## Label Evaluation Framework

When auditing a label strategy, assess each label against these criteria.

### Cardinality Scoring

| Label Example | Cardinality | Verdict |
|---|---|---|
| `service_name` / `deployment_environment` / `job` | Any | ✅ Keep key — remediate values if high-card (never drop) |
| `env` (prod/staging/dev) | 2–5 values | ✅ Good |
| `level` (info/warn/error) | 3–6 values | ✅ Good |
| `namespace` (K8s) | Tens | ✅ Acceptable |
| `instance` / `hostname` | Hundreds–thousands | ⚠️ Evaluate access patterns |
| `pod` | Thousands + transient | ⚠️ Demote off index (structured metadata) — migrate selectors first |
| `user_id`, `request_id` | Unbounded | ❌ Never use as label |

### Access Pattern Alignment
For each label, ask:
- Is this label on the protected allowlist? If yes → Keep key; remediate values only ([protected-labels.md](references/protected-labels.md))
- Is this label used as a selector in most queries targeting these logs?
- Does this label logically segment data in the way users think about it?
- Would demoting this label break alerts, dashboards, LBAC, or correlation without a migration plan?
- Would demoting this label force users to scan dramatically more data?

### Static vs. Dynamic Label Values
- **Static labels** (values don't change per log line, e.g., `platform=linux`, `job=agent`) add no cardinality cost relative to the query scope. Use freely for LBAC, exploration, and alert routing.
- **Dynamic labels** (values change per log line) must be bounded. Keep possible values in the single digits or low tens.

### Consistency Check
- Are label names consistent across services? (case-sensitive — `Level` ≠ `level`)
- Are label values normalized? (`INFO`, `info`, `Info` should all become `info`)
- Is there a naming convention? (pick one: `snake_case` or `camelCase` — be consistent)

---

## Evaluation Output Format

When auditing a label set, produce a report in the structure below.

**Hard requirements before finalizing any audit report:**

1. **Disclaimer (mandatory, first body section):** Load [references/disclaimer.md](references/disclaimer.md) and paste its two paragraphs **verbatim** under a `### Disclaimer` heading. An empty Disclaimer heading is a failed report — do not ship the audit until both paragraphs are present. Never paraphrase, summarize, or omit this text.
2. **Protected labels:** Before recommending demote/drop for any label, load [references/protected-labels.md](references/protected-labels.md). Never recommend dropping `service_name`, `deployment_environment`, or `job` when present — only value remediation. Include a **Downstream dependency check** covering alerts, dashboards, LBAC, and correlation.
3. **Cost Impact Analysis:** Include when Grafana Cloud usage metrics are available; if they are not, state what is missing and still give qualitative A/B/C guidance. Load [references/cost-impact.md](references/cost-impact.md) and follow its **Required report shape** (scenario cards). Do **not** paste markdown tables or panel/query JSON into this section.

**Report completion check:** Before delivering, confirm (a) the output contains the substring `Confidential Information of Raintank, Inc.` immediately after `### Disclaimer`, (b) Cost Impact Analysis uses scenario cards (A/B/C) with a **Billing note** opener and a bullet **Measured baseline** — not a scenario table and not `panelId`/`targets` JSON, and (c) no Action cell recommends dropping an allowlisted correlation label. If (a) is missing, paste from [references/disclaimer.md](references/disclaimer.md) and re-emit. If (b) fails, rewrite Cost Impact from [references/cost-impact.md](references/cost-impact.md). If (c) fails, rewrite Actions per [references/protected-labels.md](references/protected-labels.md).

```
## Loki Label Strategy Audit

### Disclaimer
[Paste BOTH paragraphs from references/disclaimer.md HERE — never leave this heading empty]

### Summary
[1-2 sentence overall assessment]

### Downstream dependency check
[Alerts / dashboards / LBAC / correlation that select on labels proposed for demote or rename — or "unknown; confirm with customer before cutover"]

### Label Analysis
| Label | Cardinality | Used in Queries? | Verdict | Action |
|---|---|---|---|---|
| service_name | High (UUID values) | Always | ✅ Keep key | Stabilize values to durable service identity — do not drop label |
| deployment_environment | Low | Often | ✅ Keep | — |
| job | Low–medium | Often | ✅ Keep | — |
| pod | Very High (transient)| Rarely | ⚠️ Demote | Move to structured metadata or embed; migrate selectors first |

### Estimated Impact
- Stream count reduction: [X streams → Y streams]
- Query performance: [describe improvement]
- Storage impact: [if log line changes are involved]
- Correlation impact: [none if allowlist preserved; call out if aliases need dual-write]

### Cost Impact Analysis
[Follow references/cost-impact.md Required report shape — do not invent a table]

**Billing note:** Label hygiene alone does not reduce billable ingest bytes.
Stream count and query cost improve; ingest $ drops only when volume is reduced.

**Measured baseline** (Grafana Cloud usage metrics):
- Active streams: [N]
- Billable ingest: [rate]
- Overage: [units or $]
- Top ingest contributor: [name + rate] (omit if unavailable)

**Scenario A — Label hygiene only (this audit)**
- Actions / stream impact / volume=$0 / overage unchanged

**Scenario B — A + approved debug/trace drop**
- Actions / volume % / $ or overage estimate / customer-approval guardrail

**Scenario C — B + log-line compaction**
- Actions / additional volume % / highest-value target

**Attribution gap:** [...]
**Caveats:** [...]

### Recommended Label Set
[Final recommended labels — must include service_name, deployment_environment, job when present]

### Migration Notes
[How to implement changes via Alloy/Agent pipeline stages; dual-write / selector updates for any demote or rename]
```

---

## Recommended Common Labels

Every log source should consider these base labels — all low cardinality, high query value:

| Label | Purpose |
|---|---|
| `service_name` | Identifying the generating application (OTel `service.name` — **required for Grafana Cloud correlation / App O11y**) |
| `deployment_environment` | Deployment environment (OTel `deployment.environment`) — keep when present |
| `job` | Collector / OTel job (`namespace/service.name` pattern common on span metrics) — keep when present |
| `app` / `service` | Legacy aliases only — prefer aligning to `service_name`; do not delete without a migration plan |
| `env` | Environment shorthand (prod, staging, dev) when `deployment_environment` is absent |
| `cluster` | Multi-cluster differentiation |
| `region` | Geographic region |
| `level` | Log severity — normalize to: `info`, `warn`, `error`, `debug` |
| `team` / `squad` | Ownership (also useful for LBAC) |
| `source` | Log origin type (`file`, `k8s-events`, `journal`, `syslog`, etc.) |
| `classification` | Data sensitivity level — for LBAC policies |

Always include allowlisted correlation labels in any `label_keep` list — see [references/protected-labels.md](references/protected-labels.md).

---

## Kubernetes Pod Logs

### Recommended Labels

| Label | Description |
|---|---|
| `service_name` | Stable service identity (OTel `service.name`) — **keep**; remediate UUID/ephemeral values |
| `namespace` | K8s namespace — delineates isolation boundaries |
| `container` | Container name — low cardinality, differentiates log formats |
| `workload` | `{controller_kind}/{controller_name}` e.g. `ReplicaSet/payment-api` — **strongly recommended** |

**Why `workload` beats `app` for K8s**: Derived from `{{controller_kind}}/{{controller_name}}` — static values that never change like pod names do. Unlike `app` (which may aggregate multiple workload types), `workload` is precise and predictable. Users always know exactly what value to query. Still keep `service_name` for cross-signal correlation even when using `workload`.

### Labels to demote in Kubernetes (not "never existed")

**`pod` label** ⚠️
- Highly transient: pod names change on every restart/rollout
- Very high cardinality: 5 pods × 2 containers = 10 streams; add `pod` → 10 × N streams
- Users almost never query for a specific pod; they query for the *workload*
- **Solution**: Use `workload` as the index label; store `pod` in structured metadata or embed in the log line. Migrate any alerts/dashboards that select on `pod` before demoting.

**`filename` label (raw K8s path)** ⚠️
- K8s log paths contain pod UID: `/var/log/pods/{namespace}_{pod}_{pod_id}/{container}/{rotation}.log`
- The `pod_id` component makes this unbounded
- **Solution**: Normalize to `/var/log/pods/{namespace}/{controller_name}/{container}.log` or demote entirely after checking selectors

```alloy
// Normalize K8s filename to remove pod UID
stage.replace {
 source = "filename"
 expression = "/var/log/pods/([^/]+)_[^_]+_[^/]+/([^/]+)/\\d+\\.log"
 replace = "/var/log/pods/$1/$2/current.log"
}
```

---

## Host / VM / Bare Metal Labels

In addition to common labels, add:

| Label | Description | Notes |
|---|---|---|
| `instance` | Hostname of the machine | Cardinality = number of machines; acceptable for fixed infrastructure |
| `filename` | Full path to the file being tailed | Normalize rotating filenames — strip date suffixes |

```alloy
// Remove date suffixes from rotating log file names
// /var/log/myapp/logfile-20230927.txt → /var/log/myapp/logfile.txt
stage.replace {
 source = "filename"
 expression = "-\\d{8}(\\.log|\\.txt)$"
 replace = "$1"
}
```

---

## Journal Logs

When collecting via `loki.source.journal`, many labels are auto-discovered under `__journal__*`:
`boot_id`, `cap_effective`, `cmdline`, `comm`, `exe`, `gid`, `hostname`, `machine_id`, `pid`, `stream_id`, `systemd_cgroup`, `systemd_invocation_id`, `systemd_slice`, `systemd_unit`, `transport`, `uid`

Almost all are high-cardinality. **Keep** `instance` (hostname) and `unit` (`systemd_unit`, e.g. `nginx.service`), plus any allowlisted correlation labels present on the stream (`service_name`, `deployment_environment`, `job`).

Drop other non-allowlisted high-cardinality journal labels (not platform keys):
```alloy
loki.process "journal_labels" {
 forward_to = [...]
 stage.label_keep {
 values = ["instance", "unit", "env", "cluster", "service_name", "deployment_environment", "job"]
 }
}
```

---

## Structured Metadata

Structured metadata attaches key-value pairs to log entries *without* making them index labels. The ideal home for high-cardinality values users occasionally need.

**Requires**: Loki 2.9+, Grafana Agent/Alloy. Enable via `limits_config`:
```yaml
limits_config:
 allow_structured_metadata: true
```

**Good candidates for structured metadata** (not labels):
- `pod` — K8s pod name
- `node` — K8s worker node
- `version` / `image` / `tag`
- `trace_id` / `user_id`
- `process_id`
- `restarted` — pod restart timestamp

Query structured metadata at query time without a parser:
```logql
{service_name="payment-api"} | pod="payment-api-7f9d4b-xk2r9"
```

---

## Embedding Metadata in Log Lines

When structured metadata isn't available, embed high-cardinality values into the log line rather than using them as labels.

### Method 1: stage.template (append to log line)

```alloy
loki.process "embed_pod" {
 forward_to = [...]

 // For JSON logs
 stage.match {
 selector = "{} |~ \"^\\s*\\{\""
 stage.replace {
 expression = "\\}$"
 replace = ""
 }
 stage.template {
 source = "log_line"
 template = "{{ .Entry }},\"_pod\":\"{{ .pod }}\"}"
 }
 }

 // For text logs
 stage.match {
 selector = "{} !~ \"^\\s*\\{\""
 stage.template {
 source = "log_line"
 template = "{{ .Entry }} _pod={{ .pod }}"
 }
 }

 stage.output { source = "log_line" }
}
```

Result: `ts=... msg="..." _pod=agent-logs-cqhfk`

Query by aggregate (normal use):
```logql
sum(count_over_time({workload="ReplicaSet/payment-api", level="error"}[1m]))
```

Query a specific pod (edge case debugging):
```logql
{workload="ReplicaSet/payment-api", level="error"} |= `_pod=payment-api-3`
```

### Method 2: stage.pack (JSON envelope)

```alloy
loki.process "pack_pod" {
 forward_to = [...]
 stage.pack {
 labels = ["pod"]
 ingest_timestamp = false
 }
}
```

Packed result: `{"_entry": "original log line", "pod": "agent-logs-cqhfk"}`

Unpack at query time:
```logql
{workload="ReplicaSet/payment-api", level="error"}
 |= `agent-logs-cqhfk`
 | unpack
```

---

## Performance Bottleneck Diagnosis

When a user reports slow queries, identify where time is spent using Querier `metrics.go` logs.

### Four Query Stages

| Stage | Metric | High Value Means | Fix |
|---|---|---|---|
| Queue | `queue_time` | Not enough Queriers | Add Queriers or reduce parallelism |
| Index | `chunk_refs_fetch_time` | Need more Index Gateway instances | Scale index-gateways; check CPU |
| Storage | `store_chunks_download_time` | Chunks too small OR storage bottleneck | Check avg chunk size: `total_bytes / cache_chunk_req` |
| Execution | `duration - chunk_refs_fetch_time - store_chunks_download_time` | CPU-intensive regex, or too many tiny log lines | Reduce regex; add CPU; increase parallelism |

**Ideally, the majority of time is spent in Execution.** If not, that indicates infrastructure or label design problems.

### Checking Chunk Size
```
avg chunk size = total_bytes / cache_chunk_req
```
If the result is a few hundred bytes or kilobytes (instead of megabytes), chunks are too small. This means labels are over-splitting data into too many streams. Revisit cardinality — demote non-allowlisted high-card labels or stabilize protected-label values.

### Common Label-Related Performance Problems

**Problem: Query scans too many streams**
- Cause: High-cardinality labels exist but aren't specified in the query selector
- Fix: Demote the label off the index after a migration check, or ensure queries always include it as a filter. Never demote allowlisted correlation labels — stabilize their values instead ([protected-labels.md](references/protected-labels.md))

**Problem: High `post_filter_lines` discard ratio** (`post_filter_lines << total_lines`)
- Cause: Insufficient label selectivity; query scans and discards most logs
- Fix: Add labels matching user access patterns (`level`, `workload`, `container`, `service_name`)

**Problem: Small chunks**
- Cause: Too many labels creating too many fine-grained streams
- Fix: Demote high-cardinality non-allowlisted labels (e.g. `pod`) to consolidate streams; remediate protected-label *values* if they are the splitter

### Query Optimization Quick Wins
1. Add `container` or `workload` to narrow scope before line filters
2. Add `level` label + always use it in queries (filters out 94%+ of logs when searching for errors)
3. Demote `pod` off the index → reduces stream count by ~5× in typical K8s deployments (migrate selectors first)
4. Replace regex line filters (`|~`) with exact filters (`|=`) where possible
5. Keep `service_name` (and peers); if values are UUIDs/ephemeral, normalize to a stable identity — do not drop the key

---

## Alloy / Agent Configuration Patterns

### Normalize Log Level

```alloy
loki.process "normalize_level" {
 forward_to = [...]
 stage.replace { source = "level"; expression = "(?i)I(nfo)?"; replace = "info" }
 stage.replace { source = "level"; expression = "(?i)W(arn(ing)?)?"; replace = "warn" }
 stage.replace { source = "level"; expression = "(?i)E(rr(or)?)?"; replace = "error" }
 stage.replace { source = "level"; expression = "(?i)D(ebug?)?"; replace = "debug" }
 stage.labels { values = { level = "" } }
}
```

### Conditional Meta-Label Extraction

```alloy
// Only extract when the relevant field is present — avoids unnecessary cardinality
loki.process "conditional_extraction" {
 forward_to = [...]
 stage.match {
 selector = "{app=\"loki\"} |= \"component\""
 stage.logfmt { mapping = { "component" = "" } }
 stage.labels { values = { component = "" } }
 }
}
```

### Enforce Approved Label Set (always use as final stage)

Always include allowlisted correlation labels when present — never omit `service_name`, `deployment_environment`, or `job` from `label_keep` ([protected-labels.md](references/protected-labels.md)):

```alloy
loki.process "enforce_labels" {
 forward_to = [loki.write.default.receiver]
 // ... other stages ...
 stage.label_keep {
 values = [
 "service_name", "deployment_environment", "job",
 "env", "cluster", "level", "namespace", "workload", "container",
 ]
 }
}
```

### Soft Enforcement (inject "unknown" for missing labels)

```alloy
stage.template {
 source = "team"
 template = "{{ if .Value }}{{ .Value }}{{ else }}unknown{{ end }}"
}
stage.labels { values = { team = "" } }
```

---

## Log Line Optimization

Byte-level reductions (timestamps, ANSI, null JSON fields) for Scenario C savings — see [references/log-line-optimization.md](references/log-line-optimization.md).

---

## Security & LBAC

Grafana Enterprise Logs (GEL) supports Label-Based Access Control (LBAC). Any label can serve as an access control selector.

**Best labels for LBAC**:
- `classification` — data sensitivity (`public`, `restricted`, `confidential`, `top-secret`)
- `source` — controls which teams can see which log origins
- `team` / `squad` — ownership-based access
- `env` — environment-level restrictions

Static aggregate labels like `owner=sysadmins` or `category=database` are particularly effective: one label value gates access to many log files, rather than requiring a long allowlist of filenames or streams.

---

## The 80/20 Rule

The most impactful improvements almost always come from these four changes:

1. **Demote `pod` off the index** (structured metadata) — biggest stream reduction in K8s; migrate selectors first
2. **Add `level` as a label AND always specify it in queries** — can eliminate 94%+ of scanned data when searching for errors
3. **Normalize label values** — eliminates phantom duplicate streams from inconsistent casing; for `service_name`, stabilize UUID/ephemeral values (never drop the key)
4. **Normalize or demote `filename`** in K8s — highly variable paths inflate stream count significantly

Focus on these before anything else. Never "fix" cardinality by dropping `service_name`, `deployment_environment`, or `job`.

---

## Labels to Avoid — Quick Reference

| Label | Why | Alternative |
|---|---|---|
| `pod` | Transient, high card | Demote: `workload` label + `pod` in structured metadata (migrate selectors) |
| `user_id` | Unbounded — never valid as index label | Keep only in log content |
| `request_id` / `trace_id` | Unbounded — never valid as index label | Structured metadata |
| `filename` (raw K8s path) | Contains pod UID | Normalize or demote after selector check |
| Unnormalized `level` | `INFO`/`info`/`Info` = 3 streams | Normalize at collection time |
| UUID / ephemeral `service_name` *values* | Inflates streams; key is still required | Keep key; map values to stable service identity |
| Any dynamically-named label key | Cannot be bounded | Use fixed keys with bounded values |

**Never drop:** `service_name`, `deployment_environment`, `job` — see [references/protected-labels.md](references/protected-labels.md).

---

## Cost Impact Analysis

Label hygiene alone does not cut billable ingest bytes ($0 direct). Volume savings come from enabled `stage.drop` / log-line cleanup. Load [references/cost-impact.md](references/cost-impact.md) when writing the report section: use its scenario-card shape, cite scalar metrics (optional short panel ID / PromQL), and never paste the agent-only reference table or panel JSON into the customer report.
