# Anti-patterns: what NOT to do in a skill

Distilled from [Anthropic's Agent Skills best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices), [skill-creator SKILL.md](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md), and the Tessl rubric this repo's CI gate uses.

## Description anti-patterns

### First-person / second-person voice

```yaml
# Wrong
description: I can help you process Excel files and generate reports.
description: You can use this to process Excel files.

# Right (third-person)
description: Processes Excel files and generates reports. Use when analyzing spreadsheets, building pivot tables, or generating charts from .xlsx data.
```

### Vague "what"

```yaml
# Wrong
description: Helps with metrics queries.

# Right (specific actions + concrete outputs)
description: Write PromQL queries for Prometheus and Grafana Mimir. Calculates rates, builds histogram quantiles, debugs cardinality, and optimizes slow queries. Use when writing metric queries, building Grafana panels, working with recording rules, or troubleshooting Prometheus performance.
```

### Missing "Use when" trigger

```yaml
# Wrong (no triggers — agent can't tell when to load it)
description: PromQL query writing for Prometheus.

# Right (explicit triggers)
description: PromQL query writing for Prometheus and Grafana Mimir. Use when writing metric queries, building Grafana panels, calculating rates, working with histograms, or optimizing slow queries.
```

### No trigger variations / no pushy clause

```yaml
# Wrong (only the canonical term — agent skips this when user says synonyms)
description: Use when writing k6 documentation.

# Right (variations + pushy clause)
description: ... Use when working on k6 documentation, the k6 changelog, the k6 release notes, k6 API reference, k6 TypeScript types, load testing docs - even if the user doesn't explicitly say "documentation".
```

### Reserved words in `name`

```yaml
# Wrong
name: anthropic-helper
name: claude-tools

# Right
name: skill-authoring
name: prompt-helper
```

## Body anti-patterns

### Time-sensitive language

```markdown
# Wrong (rots — "after August 2025" is meaningless in 2027)
If you're doing this before August 2025, use the old API.
After August 2025, use the new API.

# Right (`<details>` for legacy info, current path inline)
## Current method
Use the v2 API endpoint: `api.example.com/v2/messages`

<details>
<summary>Legacy v1 API (deprecated 2025-08)</summary>

The v1 API used: `api.example.com/v1/messages`. No longer supported.
</details>
```

### Windows-style paths

```markdown
# Wrong (breaks on Unix)
Run `scripts\helper.py` to process the input.

# Right (forward slashes everywhere)
Run `scripts/helper.py` to process the input.
```

### Inconsistent terminology

Pick one term per concept and stick with it. Mixing breaks Claude's pattern-matching:

```markdown
# Wrong (same concept, three names)
The API endpoint is /messages. Send a POST to the URL. The API route accepts JSON.

# Right (one term)
The API endpoint is /messages. Send a POST to the endpoint. The endpoint accepts JSON.
```

### Heavy-handed `MUST` markers without justification

```markdown
# Wrong (no explanation, feels like noise)
You MUST validate the input. You MUST handle errors. You MUST log the result.

# Right (explain why, reserve MUST for genuine hard constraints)
Validate the input before submitting — the API returns a 422 for malformed payloads
without telling you which field failed, which is hard to debug after the fact.

Always handle the 429 response with exponential backoff; the rate limiter resets
on a sliding window, not a fixed window.
```

### "There are many ways to do this" hedging

```markdown
# Wrong (forces Claude to pick — wastes time on irrelevant alternatives)
You can use pypdf, or pdfplumber, or PyMuPDF, or pdf2image. Each has trade-offs...

# Right (pick a default, mention the escape hatch)
Use pdfplumber for text extraction. For scanned PDFs requiring OCR, use pdf2image
with pytesseract instead.
```

### Dangling references

```markdown
# Wrong (file doesn't exist)
For full setup, see [references/setup-guide.md](references/setup-guide.md)
```

The linter doesn't catch this. Reviewers should. Either create the file or remove the link.

### Too-deep reference chains

```markdown
# Wrong: SKILL.md → advanced.md → details.md
# (Claude may preview with `head -100` and miss content past level 2)

# Right: keep all references one level deep from SKILL.md
SKILL.md
├── references/advanced.md
└── references/details.md
```

## Workflow anti-patterns

### Implicit ordering

```markdown
# Wrong (ordering is in the prose; easy to miss)
Configure X. Make sure to do Y before X actually. Don't forget Z either.

# Right (explicit numbered steps)
1. Do Y first
2. Then configure X
3. Then run Z to verify
```

### No validation checkpoints

```markdown
# Wrong (no way to know if step 1 worked before doing step 2)
1. Create the contact point
2. Add the notification policy
3. Write the alert rule

# Right (validate after each step)
1. Create the contact point
   - **Verify**: `curl .../api/v1/provisioning/contact-points` returns it
2. Add the notification policy
   - **Verify**: send a test alert; output should show the contact point name
3. Write the alert rule
   - **Verify**: alert fires correctly under simulated conditions
```

### "Punting to Claude" in scripts

```python
# Wrong (script lets Claude figure out failure)
def process_file(path):
    return open(path).read()   # fails on FileNotFoundError, no fallback

# Right (handle the error explicitly)
def process_file(path):
    try:
        with open(path) as f:
            return f.read()
    except FileNotFoundError:
        print(f"File {path} not found, creating default")
        with open(path, "w") as f:
            f.write("")
        return ""
```

### Voodoo constants

```python
# Wrong (no justification for the values)
TIMEOUT = 47
RETRIES = 5

# Right (self-documenting)
# HTTP requests typically complete within 30 seconds; longer timeout for slow networks
REQUEST_TIMEOUT = 30
# Three retries balances reliability vs speed; most flakes resolve by the second retry
MAX_RETRIES = 3
```

## Structural anti-patterns

### Skill body acts as a reference dump

If the skill has no workflow guidance and is just a list of API endpoints / config snippets / capabilities, the user has to do all the orchestration themselves. Tessl scores this 1-2/3 on workflow_clarity.

Fix: pick the 2-3 most common user tasks, write numbered workflows for them at the top, and move the reference-dump material to `references/<topic>.md`.

### One mega-SKILL.md when domains are clearly separable

If the skill covers AWS + GCP + Azure in one file, Claude loads all three even when the user only needs one. Split per domain:

```
cloud-deploy/
├── SKILL.md (overview + selection)
└── references/
    ├── aws.md
    ├── gcp.md
    └── azure.md
```

### Skipping marketplace registration

The skill is functionally created on disk but not installable from any marketplace. CI's `validate` job catches inter-manifest divergence but doesn't flag a skill that's missing from all three.

After creating the skill directory:

1. Add the path to `.claude-plugin/marketplace.json` → relevant plugin's `skills` array
2. Same for `.cursor-plugin/marketplace.json`
3. Same for `.agents-plugin/marketplace.json`

All three must list the same skill path. Keep them in sync.
