---
name: k6-docs
license: Apache-2.0
description: Write or review k6 documentation across the three k6 repositories - k6-DefinitelyTyped (TypeScript types), k6-docs (user documentation), and k6 (release notes / changelog). Applies k6 doc style conventions, generates TypeScript type definitions, drafts release notes, and validates examples by running them against k6@master. Use when working on k6 documentation, the k6 changelog, the k6 release notes, k6 API reference, k6 TypeScript types, load testing docs, or when the user asks to write, edit, or review anything in the k6, k6-docs, or k6-DefinitelyTyped repos - even if they don't explicitly say "documentation".
---

# k6 Documentation

Document or review k6 features across three repositories: k6-DefinitelyTyped (TypeScript types), k6-docs (user documentation), and k6 (release notes).

## Workflow

Pick the workflow that matches the user's intent:

- **Write documentation:** follow [references/workflows/write.md](references/workflows/write.md)
- **Review documentation:** follow [references/workflows/review.md](references/workflows/review.md)

## Quick References

- [Repository structure & feature type identification](references/repository-structure.md)
- [TypeScript patterns & troubleshooting](references/typescript-patterns.md)
- [Testing workflow with parallel subagents](references/testing-workflow.md)
- [agent-browser command reference](references/agent-browser-reference.md)
- [Troubleshooting guide](references/troubleshooting.md)

## Critical Rules

- **Never push automatically** - always ask first
- **Never chain commands with `&&` or `;`** - run each command separately (prevents failures)
- **Only document user-facing features** - not internal implementation
- **Use `1.` for every numbered list item** (not `1.`, `2.`, `3.`)
- **Test every code example** against k6@master before committing
- **No `Co-Authored-By: Claude` or AI attribution** in commits

## Validating examples (always run before committing)

Every code example in k6 documentation **and release notes** must execute cleanly against `k6@master`. The minimum loop:

```bash
# 1. cd into the k6 repo (not k6-docs or k6-DefinitelyTyped)
cd ~/path/to/k6

# 2. Make sure you're on master at the latest commit (the contract is k6@master)
git checkout master
git pull

# 3. Run each example as a separate command (no &&)
go run . run /path/to/script.js
```

If the run fails: read the error, fix the example in the source (doc or release note), re-run. Do not commit a change whose example doesn't run clean against current `master`. For the full multi-example workflow with parallel subagents, see [references/testing-workflow.md](references/testing-workflow.md).
