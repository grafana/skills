# Contributing to Grafana Skills

Thank you for contributing! This guide explains how to add new skills to this repository.

## What Is a Skill?

A skill is a markdown file (`SKILL.md`) with YAML frontmatter that teaches AI agents how to complete specific
tasks reliably. Skills follow the [Agent Skills](https://agentskills.io) open standard and work with Claude Code,
Cursor, and other compatible tools.

## Repository Structure

```
grafana-skills/
├── .claude-plugin/marketplace.json   # Claude Code marketplace (lists plugin groups)
├── .cursor-plugin/marketplace.json   # Cursor marketplace (identical content)
├── .agents-plugin/marketplace.json   # Codex marketplace (identical content)
├── skills/                           # All skills, grouped by plugin
│   └── <plugin-name>/<skill-name>/SKILL.md
├── template/SKILL.md                 # Starter template
└── scripts/lint-skills.sh            # Local validation
```

- **Single source of truth**: All skill content lives in `skills/`. Claude Code, Cursor, and Codex
  all reference the same files via their respective marketplace manifests.
- **Grouped by plugin**: Skills are organized under `skills/<plugin-name>/` matching the plugin
  groups in the marketplace manifests (`grafana-core`, `grafana-cloud`, `grafana-plugins`).

## Adding a New Skill

### Step 1: Create the SKILL.md

Copy `template/SKILL.md` to a new directory under the appropriate plugin group:

```bash
# Choose the right group: grafana-core, grafana-cloud, or grafana-plugins
cp -r template/SKILL.md skills/grafana-core/your-skill-name/SKILL.md
```

Fill in the frontmatter and content. See [SKILL.md format](#skillmd-format) below.

### Step 2: Validate locally

```bash
# Lint against the Agent Skills spec (checks frontmatter, naming, line count, etc.)
./scripts/lint-skills.sh skills/grafana-core

# Optional: validate using the official skills-ref tool
npx skills-ref validate skills/grafana-core/your-skill-name
```

Fix any errors or warnings before opening a PR.

### Step 3: Register in the marketplace (optional but recommended)

Add the skill path to the appropriate plugin's `skills` array in **all three** marketplace files:

```json
// .claude-plugin/marketplace.json  AND  .cursor-plugin/marketplace.json  AND  .agents-plugin/marketplace.json
{
  "plugins": [
    {
      "name": "grafana-core",
      "skills": ["./skills/grafana-core/your-skill-name"]   // add here
    }
  ]
}
```

Keep all three files identical.

### Step 4: Open a PR

Commit with a [Conventional Commit](https://www.conventionalcommits.org/) message:

```
feat(skills): add your-skill-name skill
```

---

## SKILL.md Format

Every skill must start with YAML frontmatter:

```markdown
---
name: your-skill-name        # Required: lowercase, hyphens only, max 64 chars
description: >               # Required: max 1024 chars, include "Use when..."
  What this skill does.
  Use when the user asks about X or wants to work with Y.
---

# Skill Title

Content here...
```

### Required frontmatter fields

| Field | Requirements |
|-------|-------------|
| `name` | Lowercase letters, numbers, hyphens only. Max 64 chars. Must match the directory name. |
| `description` | Max 1024 characters. Must describe what the skill does AND when to use it. Include "Use when..." trigger phrases — this is how agents decide to auto-load the skill. |

### Optional frontmatter fields

| Field | Default | Description |
|-------|---------|-------------|
| `user-invocable` | `true` | Whether users can invoke with `/skill-name` |
| `disable-model-invocation` | `false` | Prevent agents from auto-loading (use for side-effect commands) |
| `compatibility` | — | e.g. `"Claude Code, Cursor"` |
| `license` | — | e.g. `Apache-2.0` |

### Content guidelines

- **Be concise**: Only include knowledge the AI doesn't already have — Grafana-specific patterns, schemas, APIs
- **Use examples**: Code examples are more effective than prose explanations
- **Keep under 500 lines**: Split large topics into multiple focused skills
- **No "When to Use" section in the body**: Put trigger context in the `description` frontmatter instead

---

## Skill Writing Guidelines

### Descriptions are critical

The `description` field controls when agents auto-load your skill. Make it specific:

```yaml
# Good - specific triggers
description: >
  PromQL query writing for Prometheus and Grafana Mimir.
  Use when writing metric queries, building Grafana panels, calculating rates,
  working with histograms, or optimizing slow queries.

# Bad - too vague
description: Helps with metrics queries.
```

### What belongs in a skill

Include knowledge the AI is unlikely to have or gets wrong:
- Grafana-specific JSON schema fields and valid values
- Non-obvious API behaviors or quirks
- Internal conventions specific to the Grafana ecosystem
- Patterns that differ from common defaults

Do not include:
- General programming concepts or widely-known best practices
- Content from official docs that the AI already knows well
- Internal Grafana tooling, credentials, or infrastructure details

---

## Adding a New Plugin Group

If your skill doesn't fit `grafana-core`, `grafana-cloud`, or `grafana-plugins`, you can propose
a new group by adding it to all three marketplace files and updating [README.md](README.md).

New groups should represent a coherent, installable collection of related skills.

---

## Questions?

Open an issue or start a discussion on GitHub.
