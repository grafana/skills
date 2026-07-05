# Writing skill descriptions that actually trigger

The `description` field is the only part of a skill always loaded into the agent's context. Everything else — the SKILL.md body, the bundle files — is only read after the agent decides this skill applies. **If the description is weak, none of the rest of your work matters.**

## The four scoring dimensions (Tessl `descriptionJudge`)

Each rated 0-3, normalized to a 0-1 final score:

| Dimension | What it checks |
|---|---|
| **Specificity** | Lists concrete actions the skill performs (not just "helps with X") |
| **Trigger term quality** | Includes natural terms users actually say (variations, synonyms) |
| **Completeness** | Has both *what it does* AND *when to use* — usually via "Use when..." |
| **Distinctiveness / conflict risk** | Clearly scoped; won't fight other skills for activation |

## The pushy pattern (Anthropic-recommended)

From [Anthropic's skill-creator SKILL.md](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md):

> Claude has a tendency to "undertrigger" skills — to not use them when they'd be useful. To combat this, please make the skill descriptions a little bit "pushy". So for instance, instead of "How to build a simple fast dashboard to display internal Anthropic data.", you might write "How to build a simple fast dashboard to display internal Anthropic data. **Make sure to use this skill whenever the user mentions dashboards, data visualization, internal metrics, or wants to display any kind of company data, even if they don't explicitly ask for a 'dashboard.'**"

The pushy clause forces the agent to consider the skill across phrasings users actually say.

## Anatomy of a strong description

```yaml
description: <concrete-actions-the-skill-performs>. Applies <specific-conventions/methodologies>, generates <specific-outputs>, and validates <specific-checks>. Use when <task-A>, <task-B>, <task-C>, or when the user asks to <verb-1>, <verb-2>, <verb-3> - even if they don't explicitly say "<the-narrow-canonical-term>".
```

Three parts:

1. **What** — concrete actions, not vague "helps with". List specific outputs the skill produces.
2. **Use when** — explicit triggers. Multiple scenarios, ideally including domain-specific terms (repo names, CLI names, product names).
3. **Pushy clause** — the "even if they don't explicitly say…" part. This catches the user phrasings that miss the canonical term.

## Strong vs weak examples

### Weak

```yaml
# Vague "what", no "when", no trigger variations
description: Helps with k6 documentation.

# First-person, no "when"
description: I help you write k6 docs and TypeScript types.

# "When" is too narrow; missing trigger variations and pushy clause
description: Use when writing or reviewing k6 documentation across TypeScript types, user docs, and release notes.
```

### Strong (k6-docs from this repo, score 1.0/1.0 after rewrite)

```yaml
description: >
  Write or review k6 documentation across the three k6 repositories - k6-DefinitelyTyped (TypeScript types),
  k6-docs (user documentation), and k6 (release notes / changelog). Applies k6 doc style conventions,
  generates TypeScript type definitions, drafts release notes, and validates examples by running them
  against k6@master. Use when working on k6 documentation, the k6 changelog, the k6 release notes,
  k6 API reference, k6 TypeScript types, load testing docs, or when the user asks to write, edit, or
  review anything in the k6, k6-docs, or k6-DefinitelyTyped repos - even if they don't explicitly
  say "documentation".
```

Why it works:
- Specific outputs: TypeScript type definitions, release notes, example validation
- Trigger variations: changelog, release notes, API reference, repo names, "load testing docs"
- Pushy clause: catches users editing the underlying repos without saying "documentation"

## Hard limits

| Limit | Value | Source |
|---|---|---|
| Max length | 1024 chars | Agent Skills spec |
| Voice | Third-person | Anthropic best-practices doc |
| XML tags | Not allowed | Agent Skills spec |
| Reserved words in `name` (NOT description) | `anthropic`, `claude` | Anthropic best-practices doc |

## Checklist before opening a PR

- [ ] Third-person ("Processes X" not "I process X" or "You can process X")
- [ ] Explicit "Use when..." clause
- [ ] Pushy clause at the end ("even if they don't say…")
- [ ] At least 4-5 trigger-term variations users naturally say
- [ ] ≤1024 chars
- [ ] No reserved words in `name`
- [ ] Concrete actions, not "helps with"
