# The four-dimension rubric: per-dimension scoring + fix patterns

Tessl's `contentJudge` (the body-scoring half of the review) uses these four dimensions, each 0-3, weighted into the overall `reviewScore` shown in CI. The rubric is aligned with Anthropic's published best-practices doc.

## Contents

- [Conciseness](#conciseness)
- [Actionability](#actionability)
- [Workflow clarity](#workflow-clarity)
- [Progressive disclosure](#progressive-disclosure)
- [Combined heuristic: how to read a low score](#combined-heuristic)

## Conciseness

**What it scores:** Does every sentence justify its token cost? Or does the skill spend tokens explaining things Claude already knows?

**Anthropic's principle** ([best-practices doc § *Concise is key*](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)):

> Default assumption: Claude is already very smart. Only add context Claude doesn't already have. Challenge each piece of information: "Does Claude really need this explanation?" "Can I assume Claude knows this?" "Does this paragraph justify its token cost?"

**Common 2/3 patterns to cut:**

- Intro paragraphs explaining what the technology is ("PromQL is a functional query language…", "Loki is a log aggregation system…") — Claude knows
- "First, install X, then run Y, then verify Z works" prose where each step could be a one-line code block
- Repeated cautions ("never drop a distinguishing label" said three times)
- "Why this matters" paragraphs longer than the actual rule
- Verbose `<details><summary>What is X?</summary>` blocks

**Fix pattern:**

```diff
- ## Querying metrics
-
- PromQL is a functional query language that lets you query time-series data. Each query
- consists of selectors (which series), operators (what to compute), and functions (how to
- aggregate). For example, to get the request rate for an API endpoint, you'd write:
-
- ```promql
- rate(http_requests_total{job="api"}[5m])
- ```

+ ## Querying metrics
+
+ ```promql
+ rate(http_requests_total{job="api"}[5m])
+ ```
+ Standard PromQL — selector, function, range vector.
```

The code is the explanation. The prose around it was tax.

### Trim multi-example lists to 1-2 inline + defer the rest

When a section enumerates N variants of the same shape (receiver types / cloud providers / language SDKs / panel types / etc.), the judge consistently scores conciseness 2/3 if all N are inline. Reliable lift to 3/3:

- Keep the **1-2 most-common** examples inline, in full
- Move the rest to `references/<topic>.md` under a "Other X types" section, often with brief stub code + a list of remaining types
- Link from the inline section: *"For email, webhook, Teams, … see [references/X.md § Other types](references/x.md#other-x-types)"*

Concrete: in this repo, `alerting-irm` inlined four contact-point receiver types (PagerDuty, Slack, email, webhook). Conciseness stuck at 2/3. Trimming to PagerDuty + Slack inline and moving email + webhook to `references/alerting.md § Contact point receiver types` (with a list of the other 10+ supported types) lifted the score from 94 → 100 across 3 consecutive local runs.

### Other 2/3 traps observed across the catalog

The 85→100 sweep on `cue-kind-definition`, `private-connectivity`, and `skill-authoring` surfaced these recurring conciseness traps. The judge's verbatim suggestion text is in italics — quoting it because the wording is consistent enough to grep for in future reviews.

- **"When to use this skill" bulleted lists** — overlap with the description's "Use when…" clause. *"the 'when to use this skill' list overlaps heavily with what should be in the description"*. Fix: delete the section entirely; the description is the trigger.
- **Multi-row tables that delegate to refs** — each cell is a one-line summary + ref link. *"the rubric table could be leaner since it mostly points to references"*. Fix: replace with a one-sentence summary + single ref link.
- **Cost / savings / business-value tangents** — dollar amounts, ROI calculations, "this saves N% on…". *"includes some unnecessary content like the cost savings section with specific dollar calculations"*. Fix: move to `references/<topic>.md § Cost`.
- **Bare decision-table rows** — single-line entries with no actionable content ("On-premises with no cloud provider — use Agent over internet"). *"the 'On-premises with no cloud provider' row"*. Fix: drop the row.
- **Multi-paragraph "Why X" explanations** — explaining the rationale at length. *"the 'Score variance' section spends many lines explaining LLM judge variance which could be condensed to 2-3 lines"*. Fix: collapse to one sentence stating the rule + one stating the reason.
- **Anti-patterns lists that duplicate critical rules** — *"the anti-patterns section partially duplicates the critical rules"*. Fix: either fold uniques into the rules, or replace the section with a one-line pointer to `references/anti-patterns.md`.
- **Intro paragraphs of the form "X drives the entire Y pipeline; each X describes…"** — orientation prose Claude doesn't need. *"the opening paragraph explaining what kinds drive and what gets generated from them is context Claude can infer"*. Fix: delete and start with the first workflow.

### Read the judge's suggestions, don't guess

`tessl skill review` (without `--json`) prints an `Assessment:` paragraph and `Suggestions:` bullets per dimension. **The Suggestions block names the exact sentences/sections to cut.** Copy them directly. Across this repo's 85→100 fixes, *every* lift came from applying the verbatim suggestion — guessing what to trim consistently took longer and lifted less.

## Actionability

**What it scores:** Could Claude, reading this once, do the task copy-paste? Or does Claude have to fill gaps from its own knowledge?

**Strong patterns:**

- Copy-paste-ready CLI commands with concrete arguments (not placeholders like `<your-token>` everywhere)
- Complete config snippets, not "configure X like Y"
- Templates with explicit `[Title]` / `[Section]` placeholders the user can fill
- Explicit `Input:` / `Output:` pairs for output-shape teaching

**Weak patterns (the 2/3 trap):**

- "Use the appropriate library to do X" without naming the library
- Placeholders that hide ambiguity: "Set the value to <appropriate>"
- "There are many ways to do this, here are some…" — pick one, ship it
- Discussing trade-offs before showing the solution

**Fix pattern:**

```diff
- ### Setup
-
- You'll need to configure Alloy with the appropriate scrape targets. Most users will want
- to start with a basic configuration and extend it.

+ ### Setup
+
+ ```alloy
+ prometheus.scrape "node_exporter" {
+   targets    = [{"__address__" = "localhost:9100"}]
+   forward_to = [prometheus.remote_write.default.receiver]
+ }
+
+ prometheus.remote_write "default" {
+   endpoint {
+     url = sys.env("PROMETHEUS_REMOTE_WRITE_URL")
+   }
+ }
+ ```
```

## Workflow clarity

**What it scores:** Multi-step procedures with explicit ordering, decision points, and validation checkpoints.

**Strong patterns:**

- Numbered steps where order matters
- Explicit `if validation fails, do X; else continue` branches
- A copy-able checklist Claude can paste into its response
- Validate → fix → re-run feedback loops written out

**Weak patterns:**

- Bullet list of capabilities with no ordering
- "Configure X, then Y, then Z" without per-step validation
- No "what to do if it fails" guidance
- Implicit ordering ("Make sure to do A. By the way, you also need B before A")

**Fix pattern:**

```diff
- ## Setting up alerts
-
- Create contact points, add notification policies, write the alert rules. Make sure to
- test routing before going live.

+ ## Setting up alerts
+
+ 1. **Create contact points** (where notifications go):
+    ```bash
+    curl -X POST .../api/v1/provisioning/contact-points -d @contact-points.json
+    # Verify:
+    curl .../api/v1/provisioning/contact-points | jq '.[].name'
+    ```
+
+ 2. **Add notification policies** (which alerts go where):
+    ```bash
+    curl -X POST .../api/v1/provisioning/policies -d @policies.json
+    ```
+
+ 3. **Write alert rules**:
+    ```bash
+    curl -X POST .../api/v1/provisioning/alert-rules -d @rules.json
+    ```
+
+ 4. **Verify routing** before going live:
+    ```bash
+    curl -X POST .../api/v1/provisioning/policies/test -d @test-alert.json
+    # If output doesn't show the expected contact point, re-check matchers in step 2.
+    ```
```

The "verify" + "what to do if it fails" steps are what lift a workflow_clarity score from 2 to 3.

## Progressive disclosure

**What it scores:** Are you using the three-level loading model correctly? Or is everything dumped into one 600-line SKILL.md?

**The three levels** ([skill-creator SKILL.md](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md)):

1. **Metadata** (name + description) — always loaded, ~100 words
2. **SKILL.md body** — loaded when the skill triggers, <500 lines
3. **Bundled resources** (scripts/, references/, assets/) — loaded only when needed

**Strong patterns:**

- SKILL.md under 200 lines for the routing layer
- `references/*.md` for detailed material, linked one level deep
- Domain-organized refs: `references/aws.md`, `references/gcp.md`, `references/azure.md` (Claude reads only the relevant one)
- Reference files >100 lines have a table of contents at the top

**Weak patterns:**

- One 800-line SKILL.md with sections that should be separate files
- Nested references: `SKILL.md → a.md → b.md` (Claude may truncate at level 2)
- Dangling references — `[see X](references/x.md)` where the file doesn't exist
- All content inline even when there are clear domain boundaries

**Fix pattern (split):**

Before:
```
skills/grafana-cloud/admin/
└── SKILL.md  (244 lines, includes SSO config, Terraform examples, full API endpoint reference)
```

After:
```
skills/grafana-cloud/admin/
├── SKILL.md            (under 100 lines: overview, workflows, RBAC, service accounts)
└── references/
    ├── sso.md          (OAuth + SAML + GitHub OAuth configs)
    ├── terraform.md    (Terraform examples)
    └── api-reference.md (Cloud API + Admin endpoints + audit logs)
```

Then SKILL.md links to each `references/*.md` one level deep.

### When NOT to split

Some skills are intentionally short routing documents (e.g. `grafana-k6/k6-docs` — 33 lines of overview pointing at a deep `references/workflows/*.md` bundle). The four-dimension rubric penalizes these for "not independently actionable", BUT the architecture is correct.

For routing documents: add a minimal copy-paste-ready "validation loop" inline so SKILL.md is independently actionable for the most common task, while preserving the bundle for everything else. See `skills/grafana-k6/k6-docs/SKILL.md` for the pattern that lifted its score from 72 → 100 without losing the bundle.

### The "bundle files weren't provided" 2/3 ceiling

`tessl skill review` (and CI) only reads SKILL.md — not files under `references/`. The LLM judge sees the link in SKILL.md but cannot verify the target exists, so it caps progressive_disclosure at 2/3 with the line *"no bundle files were provided, so the references are dangling"*. Two responses:

- **Login locally**: `tessl login`, then `tessl skill review` includes bundle files in the judgment (output note: *"Only SKILL.md was reviewed. Log in with tessl login to include all supporting files in the review."*). CI doesn't login, so this only helps local-only sanity checks.
- **Don't write your way into the trap**: a skill that *itself* names "dangling references" as a danger triggers the judge's caution explicitly. If your SKILL.md uses references heavily, keep the dangling-references warning in `references/anti-patterns.md` rather than in the body.

## Combined heuristic

If you see a 2/3 across all four dimensions, the skill is doing too much narrative and not enough structure. If just one dimension is low:

| Low dimension | First fix to try |
|---|---|
| Conciseness | Cut the introduction. Cut explanations of what known technologies are. |
| Actionability | Replace one prose paragraph per section with a code block. |
| Workflow clarity | Add numbered steps + one validation step per workflow. |
| Progressive disclosure | Split sections >50 lines into `references/*.md`. |

Then re-run `tessl skill review --json` and iterate. Score lift per fix is typically 5-15 points.
