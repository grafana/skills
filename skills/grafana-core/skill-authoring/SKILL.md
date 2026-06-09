---
name: skill-authoring
license: Apache-2.0
description: Author, audit, and improve Grafana SKILL.md files against Anthropic's published Agent Skills guidance and the four-dimension rubric the grafana/skills CI gate uses (conciseness, actionability, workflow clarity, progressive disclosure). Applies the canonical SKILL.md structure (YAML frontmatter + body + references/ + scripts/ + assets/), the "pushy description" trigger pattern, the three-level progressive-disclosure model, and the validate-fix-rerun feedback loop. Use when creating a new skill in this repo, when reviewing a skill PR, when a skill's Tessl review score is below 75 (the merge gate), when a skill's description isn't getting picked up by agents, when restructuring a long SKILL.md into a bundle, or when the user asks how to write, improve, optimize, audit, or fix a skill - even if they don't say "skill" explicitly (e.g. "this isn't triggering", "Tessl scored this 72", "split this doc").
---

# Authoring & Improving Grafana Skills

How to write, review, and improve SKILL.md files so they pass the repo's CI gate and score well against the Anthropic-aligned rubric Tessl uses.

## Critical rules (always)

1. **Description is the primary trigger** — third-person, ≤1024 chars, must include explicit "Use when..." phrasing AND list concrete trigger terms users naturally say. See [references/descriptions.md](references/descriptions.md) for the pushy-description pattern that combats undertriggering.
2. **Body under 500 lines** — split into `references/*.md` if approaching the limit. SKILL.md is the routing layer, not the entire knowledge base.
3. **One level of nesting for references** — link from SKILL.md directly, never `SKILL.md → a.md → b.md`. Claude may use `head -100` previews on nested chains and miss content.
4. **Imperative voice** — "Run X" not "You should run X" not "It is important to run X". Explain *why* over heavy-handed `MUST` markers.
5. **Concrete examples beat prose** — copy-paste-ready commands, real config snippets. Tessl's `actionability` dimension scores this directly.
6. **No reserved words in `name`** — `anthropic` and `claude` are forbidden in skill names.
7. **No time-sensitive language in the body** — "after August 2025…" rots. Use an `<details>` "Old patterns" section for legacy info instead.
8. **Validate before committing** — `./scripts/lint-skills.sh skills/<plugin>/<your-skill>` clean + Tessl score ≥75 (run `tessl skill review --json <dir>`).

## The rubric

CI fails any PR where a touched SKILL.md scores below **75** on four 0-3 dimensions: **conciseness**, **actionability**, **workflow clarity**, **progressive disclosure**. Full per-dimension scoring + Anthropic-doc mapping in [references/rubric.md](references/rubric.md).

## Score variance

The judge is an LLM and swings 7-10 points run-to-run. Local 94 commonly lands at CI 85. **Ship only on three consecutive local 100s.**

## Decision tree for a new skill

1. **What product / domain does this skill belong to?**
   Pick the right plugin folder: `grafana-core/`, `grafana-cloud/`, `grafana-lgtm/`, `grafana-app-sdk/`, `grafana-k6/`, `grafana-plugins/`. If none fits cleanly, ask the user before creating a new plugin group (a new group requires updating three `marketplace.json` files).

2. **Estimate body length.**
   - <200 lines of substance → single `SKILL.md`, no bundle
   - 200-500 lines → `SKILL.md` + `references/<topic>.md` for the long-form material
   - >500 lines → mandatory bundle split; see [references/anatomy.md § Splitting strategies](references/anatomy.md#splitting-strategies)

3. **Write a "pushy" description first.**
   The description is the only thing always loaded into context. If agents don't trigger the skill, nothing else matters. See [references/descriptions.md](references/descriptions.md) for the pattern.

4. **Draft body with the four-dimension rubric in mind.**
   - Cut every sentence Claude already knows (Conciseness)
   - Replace prose explanations with code blocks (Actionability)
   - Number every multi-step procedure + add a validation step at the end (Workflow clarity)
   - If you reach for `<details>`, consider whether that content belongs in `references/` instead (Progressive disclosure)

5. **Register in marketplace manifests.**
   Add the skill path to the `skills` array in all three:
   - `.claude-plugin/marketplace.json`
   - `.cursor-plugin/marketplace.json`
   - `.agents-plugin/marketplace.json`

6. **Validate locally.**
   ```bash
   # 1. Lint clean (0 errors)
   ./scripts/lint-skills.sh skills/<plugin>/<your-skill>

   # 2. Tessl reviewScore ≥75 (the CI gate)
   tessl skill review --json skills/<plugin>/<your-skill> | jq '.review.reviewScore'

   # 3. If below 75 or you want ≥85: run --optimize (requires auth)
   tessl skill review --optimize --yes --max-iterations 3 skills/<plugin>/<your-skill>
   ```

   If the run fails: read the lint error / Tessl suggestion, fix, re-run. Don't open the PR until both checks pass cleanly. The feedback-loop pattern beats one-shot writing.

## Fixing a low-scoring existing skill

1. Read the judge's verbatim Suggestions text (non-JSON output):
   ```bash
   tessl skill review skills/<plugin>/<name>
   ```
   The `Suggestions:` block under each dimension names the exact sentences/sections to cut. **Copy the suggestion** — don't guess. Then verify the lowest dimension matches your read.

2. Apply the fix pattern from [references/rubric.md](references/rubric.md):
   - **Conciseness 1-2** → cut intros, definitions, multi-line tables that mostly point to refs
   - **Actionability 1-2** → replace prose with code blocks and CLI commands
   - **Workflow clarity 1-2** → add numbered steps + validation checkpoints
   - **Progressive disclosure 1-2** → split into `references/*.md`

3. If the skill is **intentionally a routing document** (like `grafana-k6/k6-docs`), don't let `--optimize` inline the bundle back into SKILL.md. Hand-craft a minimal copy-paste "validation loop" inline so SKILL.md is independently actionable, while preserving the bundle.

4. Re-score five times locally. **Don't stop until all five runs hit 100** — see "Score variance" above for why.

## Anti-patterns

See [references/anti-patterns.md](references/anti-patterns.md).

## References

- [`references/descriptions.md`](references/descriptions.md) — the pushy-description pattern + trigger-term checklist
- [`references/rubric.md`](references/rubric.md) — per-dimension scoring with Anthropic-doc citations and concrete fix patterns
- [`references/anatomy.md`](references/anatomy.md) — three-level progressive disclosure, bundle layout, splitting strategies
- [`references/anti-patterns.md`](references/anti-patterns.md) — what NOT to do, with examples
- [Anthropic — Agent Skills best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- [anthropics/skills — skill-creator SKILL.md](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md)
- [The Complete Guide to Building Skills for Claude (PDF)](https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf)
