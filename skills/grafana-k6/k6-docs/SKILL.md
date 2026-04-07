---
name: k6-docs
license: Apache-2.0
description: Use when writing or reviewing k6 documentation across TypeScript types, user docs, and release notes.
---

# k6 Documentation

Document or review k6 features across three repositories: k6-DefinitelyTyped (TypeScript types), k6-docs (user documentation), and k6 (release notes).

## Workflow

Based on user's action, follow the appropriate workflow:

- **Write Documentation:** [Complete write workflow](references/workflows/write.md)
- **Review Documentation:** [Complete review workflow](references/workflows/review.md)

## Quick References

- [Repository structure & feature type identification](references/repository-structure.md)
- [TypeScript patterns & troubleshooting](references/typescript-patterns.md)
- [Testing workflow with parallel subagents](references/testing-workflow.md)
- [agent-browser command reference](references/agent-browser-reference.md)
- [Troubleshooting guide](references/troubleshooting.md)

## Critical Rules

- Never push automatically - always ask first
- Never chain commands with `&&` or `;` - run each command separately (prevents failures)
- Only document user-facing features - not internal implementation
- Use `1.` for all numbered list items (not 1., 2., 3.)
- Test with k6@master: first `cd /path/to/k6`, then `go run . run script.js` for each example
- No "Co-Authored-By: Claude" or AI attribution
