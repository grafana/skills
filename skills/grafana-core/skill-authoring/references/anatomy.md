# Anatomy of a skill bundle

## The canonical layout

```
skills/<plugin>/<skill-name>/
├── SKILL.md              (required: YAML frontmatter + body)
├── references/           (markdown loaded only when needed)
│   ├── topic-a.md
│   └── topic-b.md
├── scripts/              (executable code; not loaded into context)
│   └── helper.py
└── assets/               (templates, fonts, images used as output)
    └── template.json
```

Source: [anthropics/skills — skill-creator SKILL.md § Anatomy of a Skill](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md).

## The three-level loading model

| Level | What's loaded | When | Token cost |
|---|---|---|---|
| 1. Metadata | `name` + `description` | Always (at agent startup) | ~50-200 tokens per skill |
| 2. SKILL.md body | Full markdown body | When the agent decides the skill triggers | ~500-3000 tokens once loaded |
| 3. Bundle | `references/*.md`, `assets/*`, `scripts/*` (via bash, not context) | On demand, only the specific file the body links to | Zero until accessed |

Implication: **the cheapest way to lift Conciseness is to move heavy content from level 2 to level 3.**

## SKILL.md size guidance

- **Aim:** ≤200 lines for the body
- **Hard guideline:** ≤500 lines (Anthropic's documented limit)
- **Soft threshold:** If you're past 250 lines, ask whether some sections should be `references/*.md`

## Splitting strategies

### By domain (when a skill spans multiple platforms/frameworks)

```
cloud-integrations/
├── SKILL.md           (overview + selection logic: "if AWS, see references/aws.md…")
└── references/
    ├── aws.md
    ├── gcp.md
    ├── azure.md
    └── confluent.md
```

Claude reads SKILL.md, sees the user mentioned AWS, reads only `references/aws.md`. The other three never load → zero token cost.

### By depth (when overview vs. detail is clear)

```
react-19-plugin-migration/
├── SKILL.md           (decision tree + critical rules + happy path)
└── references/
    ├── eslint-9-migration.md  (deep dive for the ESLint sub-step)
    └── troubleshooting.md     (failure modes + fixes)
```

### By format (when reference material doesn't fit the prose flow)

```
admin/
├── SKILL.md
└── references/
    ├── sso.md           (full OAuth/SAML/GitHub OAuth configs)
    ├── terraform.md     (Terraform provider examples)
    └── api-reference.md (Cloud API + Admin endpoints + audit logs)
```

## Reference-file conventions

- **Filename**: short, descriptive, lowercase-with-hyphens (`troubleshooting.md`, not `Troubleshooting.md` or `Docs.md`)
- **Top of file**: if >100 lines, include a `## Contents` table of contents so Claude can navigate during a partial read
- **Linked one level deep from SKILL.md** — never a chain (`SKILL.md → a.md → b.md`)
- **Inline relative links** — `[full setup guide](references/sso.md)` from SKILL.md, not absolute URLs

## When NOT to inline

Tessl's rubric penalizes routing documents (a thin SKILL.md that defers to references/) by scoring them down for "not independently actionable". The naive response is to inline content from references back into SKILL.md, which undoes the deliberate progressive disclosure.

**Better fix for routing skills:** add a minimal copy-paste-ready "happy path" loop inline so SKILL.md is independently actionable for the most common task, while preserving the bundle for everything else.

Concrete example — `grafana-k6/k6-docs` (33 lines in its SKILL.md):

````markdown
## Workflow

Pick the workflow that matches the user's intent:

- **Write documentation:** follow [references/workflows/write.md](references/workflows/write.md)
- **Review documentation:** follow [references/workflows/review.md](references/workflows/review.md)

## Validating examples (always run before committing)

Every code example in k6 documentation and release notes must execute cleanly against `k6@master`:

```bash
cd ~/path/to/k6
git checkout master
git pull
go run . run /path/to/script.js
```

If the run fails: read the error, fix the source, re-run. Don't commit a doc edit whose
example doesn't run clean. For the full multi-example workflow with parallel subagents,
see [references/testing-workflow.md](references/testing-workflow.md).
````

This pattern (the file lifted its score from 72 → 100):
1. Keeps the routing layer + bundle architecture
2. Adds enough inline content that Claude can do the common task without loading any bundle file
3. Still defers full procedural detail to the references/

## scripts/ directory

Use when the skill includes deterministic operations Claude shouldn't reinvent:
- File transformations (PDF extraction, image resizing)
- Validation harnesses
- Output formatters

Scripts are executed via bash; **their contents do not consume context tokens**, only their output does. Big performance win for skills that run the same code repeatedly.

Make scripts executable (`chmod +x`) — the linter warns otherwise.

## assets/ directory

Use for template files, fonts, images, or other static resources the skill produces as output. Like scripts, assets don't consume tokens until referenced.

## Marketplace registration

After creating the skill directory, add it to the `skills` array in all three marketplace files:

- `.claude-plugin/marketplace.json`
- `.cursor-plugin/marketplace.json`
- `.agents-plugin/marketplace.json`

The three must stay in sync. CI's `validate` job will fail any PR where they diverge.
