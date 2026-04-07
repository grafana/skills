# Review Documentation Workflow

Validate k6 documentation across three repositories in parallel using specialized review agents.

## Prerequisites

**agent-browser for visual verification:**
- Run `${CLAUDE_PLUGIN_ROOT}/skills/k6-docs/scripts/check_agent_browser.sh` to install if needed
- See [agent-browser reference](../agent-browser-reference.md) for command list
- Fallback: Use `curl` for HTTP status checks only (no visual verification)

**Local docs server must be running:**
- Automatically confirm `npm start` running in k6-docs at http://localhost:3002, or ask user to start it

**k6 repository on master branch:**
- Required for testing examples: `cd /path/to/k6`, then `git checkout master`

## Initial Setup

Ask user for branch names (or pull from PR if applicable):
- k6-docs branch (e.g., `add/page-waitForEvent`)
- k6-DefinitelyTyped branch (e.g., `add/page-waitForEvent`)
- k6 release branch (e.g., `release-1.5.0` or `release-v1.5.0`)

## Workflow

Launch THREE review agents IN PARALLEL using Task tool in a SINGLE message.

Use prompts from [Subagent prompts](../subagent-prompts.md):
1. TypeScript Review - Validates type definitions and tests using [TypeScript checklist](../checklists/typescript.md)
2. Documentation Review - Validates user docs, links, and examples using [Documentation checklist](../checklists/documentation.md)
3. Release Notes Review - Validates release notes content using [Release notes checklist](../checklists/release-notes.md)

Each agent checks out specified branch and reports structured findings.

## Critical Rules

- **Never chain commands** with `&&` or `;` - run separately (prevents failures)
- **MUST execute code examples:** Use [Testing workflow](../testing-workflow.md) with parallel subagents
- **MUST validate links:** Use git diff + grep + curl pipeline (see [Documentation checklist](../checklists/documentation.md))
- **MUST visual verify:** Use agent-browser for screenshots (see [agent-browser reference](../agent-browser-reference.md))
- **If ALL examples have skip markers:** Report ⚠️ UNTESTED, not ✅ PASS - nothing was verified
- **Pre-existing failures:** Focus on ensuring NEW changes don't add errors (see [Troubleshooting](../troubleshooting.md))

## Final Report Format

After all three subagents complete:

```
# Documentation Review Summary: [FEATURE_NAME]

## Overall Status: [PASS / ISSUES FOUND]

## TypeScript Definitions
[Subagent 1 results]

## User Documentation
[Subagent 2 results]

## Release Notes
[Subagent 3 results]

## Action Items
1. [Required fixes]
2. [Recommended improvements]

## Ready to Merge?
[YES - all checks pass / NO - issues must be fixed first]
```

If issues found, ask user if they want you to fix them.
