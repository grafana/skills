# Testing Workflow for k6 Examples

**REQUIRED:** All code examples in documentation and release notes must be tested with k6@master using `go run . run script.js`.

## Testing Loop

Follow this loop until 100% of examples pass:

1. Extract runnable examples (skip blocks with `<!-- md-k6:skip -->` comment)
1. Set up dependencies if needed (test servers, mock APIs, etc.)
1. Launch parallel subagents to test each example (one Task per example in single message)
1. If failures: launch fix subagent → update docs → re-test ALL examples
1. Repeat until 100% pass

## Testing Subagent Template

Use this template for each example test subagent (Bash subagent type):

```
Test example <N>: <brief description>

1. Write code to /tmp/k6-test-<name>-<N>.js
2. Run: cd /path/to/k6
3. Run: go run . run /tmp/k6-test-<name>-<N>.js
4. Report: SUCCESS or FAILURE with exit code and full output
5. Clean up temp file
```

## Fix Subagent Template

When examples fail, use this template (general-purpose subagent):

```
Fix failing examples: [list failures with errors]

1. Analyze failures (API errors, missing imports, timing issues, etc.)
2. Update docs: docs/sources/k6/next/javascript-api/[...]/[method].md
3. Report changes made

allowed-tools: Read, Edit, Grep, Glob
```

## Parallel Launch Pattern

**IMPORTANT:** Launch all test subagents IN PARALLEL using the Task tool.

Send a **SINGLE message** with MULTIPLE Task tool calls to run them simultaneously:

```
Message structure:
- Text explaining what you're testing
- [Invoke Task tool: Test example 1]
- [Invoke Task tool: Test example 2]
- [Invoke Task tool: Test example 3]
- ...
```

This runs tests concurrently instead of waiting for each to finish sequentially.

## After All Examples Fail/Pass

If ALL examples have `<!-- md-k6:skip -->` markers:
- Status is ⚠️ **UNTESTED** (NOT ✅ PASS)
- Flag this as a concern: "No examples were actually tested"
- Question whether skip markers are appropriate
- This is NOT a success - nothing was verified

Do NOT use ✅ or report PASS/SUCCESS/VERIFIED unless you actually ran `go run . run` and it succeeded.

## Prerequisites

k6 repository must be on `master` branch for testing:
```bash
cd /path/to/k6
git checkout master
git pull origin master
```
