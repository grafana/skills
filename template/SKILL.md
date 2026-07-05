---
name: your-skill-name
description: >
  Clear description of what this skill does and when to use it.
  Use when the user asks about X or wants to work with Y.
  Include specific trigger phrases so agents auto-load it correctly.
  Max 1024 characters.

# ── Agent Skills spec fields (https://agentskills.io/specification) ──────────
# license: Apache-2.0                    # Recommended for open-source skills
# compatibility: Claude Code, Cursor     # Only if skill has specific env requirements (max 500 chars)
# metadata:                              # Custom key-value pairs
#   author: grafana-labs
# allowed-tools: Bash(git:*) Read        # Pre-approved tools (experimental)

# ── Claude Code extension fields (not part of the spec) ──────────────────────
# user-invocable: true                   # Show in / menu (default: true)
# disable-model-invocation: false        # Prevent agent auto-loading (default: false)
---

# Your Skill Title

## Overview

Brief introduction to what this skill covers. Focus on Grafana-specific knowledge — don't explain
general programming concepts the AI already knows well.

## Key Concepts

Document the important concepts, patterns, or syntax. Code examples are more effective than prose.

```promql
# Example
rate(http_requests_total[5m])
```

## Common Patterns

Describe the most frequently needed patterns or configurations.

## Best Practices

- List recommendations specific to this skill's domain
- Include common pitfalls to avoid

---

> **Keep SKILL.md under 500 lines.** Move detailed reference material to `references/` files and
> link to them from here. See [agentskills.io/specification](https://agentskills.io/specification).
