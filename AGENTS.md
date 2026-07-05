# AGENTS.md

Instructions for AI agents working with this repository.

## Repository Purpose

This is the Grafana public skills repository — a plugin marketplace providing AI-assisted development skills
for Claude Code, Cursor, and other tools supporting the [Agent Skills](https://agentskills.io) standard.

Skills cover Grafana, Prometheus, Loki, Tempo, Pyroscope, k6, and the broader LGTM observability stack.

## Structure Overview

```
.claude-plugin/marketplace.json    # Claude Code marketplace manifest
.cursor-plugin/marketplace.json    # Cursor marketplace manifest (identical content)
.agents-plugin/marketplace.json    # Codex marketplace manifest (identical content)
skills/                            # All skills, grouped by plugin
  <plugin-name>/
    <skill-name>/
      SKILL.md                     # Required: skill definition
      scripts/                     # Optional: executable helper scripts
      references/                  # Optional: reference docs loaded on demand
      assets/                      # Optional: templates, schemas, data files
template/SKILL.md                  # Starter template for contributors
scripts/lint-skills.sh             # Validates SKILL.md files
```

**Key architecture:**

- Single source of truth in `skills/` — Claude Code, Cursor, and Codex all reference the same content
- Three marketplace manifests (`.claude-plugin/`, `.cursor-plugin/`, `.agents-plugin/`) with identical content
- `skills/` is the conventional directory used by all major agent tools

## How Skills Work

Skills are folders of instructions, scripts, and resources that agents load dynamically when relevant.

1. The agent reads the skill's `description` frontmatter
2. When the context matches, the agent loads the full `SKILL.md`
3. Supporting files in `scripts/` and `references/` are loaded on demand

### Invocation Modes

Two frontmatter fields control who can invoke a skill:

**`disable-model-invocation`** (default: `false`):
- `false`: Agent may auto-load when context matches
- `true`: Agent will never auto-load; only runs when user types `/skill-name`

**`user-invocable`** (default: `true`):
- `true`: Appears in the `/` menu, user can call with `/skill-name [arguments]`
- `false`: Hidden from menu; only the agent can load it (background knowledge)

| `user-invocable` | `disable-model-invocation` | User | Agent | Use case |
|------------------|---------------------------|------|-------|----------|
| `true` (default) | `false` (default)         | Yes  | Yes   | Most skills |
| `true`           | `true`                    | Yes  | No    | Side-effect operations (`/deploy`, `/send`) |
| `false`          | `false`                   | No   | Yes   | Background knowledge (conventions, guidelines) |

### Dynamic Arguments

Skills can accept user input via `$ARGUMENTS`:

```markdown
---
name: greet
description: Greet a user by name. Use when /greet is invoked.
---
Hello, $ARGUMENTS!
```

Usage: `/greet Alice` → "Hello, Alice!"

## When Adding New Skills

1. Create `skills/<plugin-name>/<skill-name>/SKILL.md` following the template at `template/SKILL.md`
   - Plugin groups: `grafana-core`, `grafana-cloud`, `grafana-plugins`
2. Use the spec: name (lowercase, hyphens, max 64 chars), description (max 1024 chars, include "Use when...")
3. Run `./scripts/lint-skills.sh skills/<plugin-name>` to validate
4. Register the skill in both marketplace files under the appropriate plugin group
5. Update `README.md` to list the new skill

## When Adding Supporting Files

Skills can include:
- `scripts/` — executable scripts, referenced from SKILL.md with relative paths
- `references/` — detailed docs split out for progressive disclosure (keeps SKILL.md under 500 lines)
- `assets/` — templates, JSON schemas, data files

Reference scripts using relative paths from the skill directory, or use `${CLAUDE_PLUGIN_ROOT}` for
plugin-root-relative paths when installed via Claude Code:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/grafana-core/your-skill/scripts/your-script"
```

## Skill Writing Guidelines

- **Be concise**: Only include Grafana-specific knowledge the AI doesn't already have
- **Use examples**: Code examples are more effective than explanations
- **Include triggers in description**: The description determines when the skill auto-activates
- **Keep under 500 lines**: Split large topics into multiple focused skills
- **Use `disable-model-invocation: true`** for command-style skills that should only run when explicitly invoked

## Distribution

### Claude Code

```bash
claude plugin marketplace add grafana/skills
claude plugin install grafana-core@grafana-skills
```

### Cursor

Settings - Rules, Skills, Subagents - Add from GitHub - `https://github.com/grafana/skills`

### Other tools

Any tool supporting the [Agent Skills](https://agentskills.io) standard or the `skills/` convention
(including [vercel-labs/skills](https://github.com/vercel-labs/skills) CLI) can consume skills directly.

## Do Not

- Add README.md or other docs inside skill directories
- Put "When to Use" sections in the skill body (put in `description` frontmatter instead)
- Add internal Grafana tooling, credentials, or infrastructure-specific content
- Hardcode script paths — use relative paths or `${CLAUDE_PLUGIN_ROOT}`
- Edit `.claude-plugin/marketplace.json` without making the identical change to `.cursor-plugin/marketplace.json` and `.agents-plugin/marketplace.json`

## Official Resources

- [Claude Code Docs - Plugins](https://code.claude.com/docs/en/plugins)
- [Claude Code - Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)
- [Agent Skills Standard](https://agentskills.io)
- [Agent Skills Specification](https://agentskills.io/specification)
- [Anthropic Skills Repository](https://github.com/anthropics/skills)
