# Subagent Review Prompts

Use these prompts when launching parallel review agents via Task tool.

## TypeScript Review Subagent

```
Review TypeScript definitions for [FEATURE_NAME].

Branch: [BRANCH_NAME]
Locate k6-DefinitelyTyped repository in current directory or subdirectories.

1. Checkout the branch:
   cd k6-DefinitelyTyped
   git checkout [BRANCH_NAME]

2. Check what changed:
   git log main..HEAD --oneline
   git diff main --stat

3. Read the changed type definition files in types/k6/

4. Review against checklist in references/review-checklists.md (TypeScript section)

5. Run tests:
   pnpm install -w --filter "{./types/k6}..."
   pnpm test k6

6. Report findings:
   ## TypeScript Review: [FEATURE_NAME]
   **Status:** PASS / ISSUES FOUND
   **Commits:** [list]
   **Files Changed:** [list]
   **Checklist Results:** [each item with PASS/FAIL]
   **Test Results:** [pass/fail with details]
   **Issues Found:** [list]
   **Recommendations:** [list]
```

## Documentation Review Subagent

```
Review user documentation for [FEATURE_NAME].

Branch: [BRANCH_NAME]
Local server: http://localhost:3002
Locate k6-docs repository in current directory or subdirectories.

1. Checkout the branch:
   cd k6-docs
   git checkout [BRANCH_NAME]

2. Check what changed:
   git log main..HEAD --oneline
   git diff main --stat

3. Validate ALL added links with ${CLAUDE_PLUGIN_ROOT}/skills/k6-docs/scripts/validate_links.sh

4. Visual verification with agent-browser (or curl fallback):
   agent-browser open "http://localhost:3002/docs/k6/next/javascript-api/[module]/[method]/"
   agent-browser screenshot --full method-page.png

   Verify page loads, parameters table, code highlighting, links, breadcrumbs

5. Read each changed documentation file and review against checklist in references/review-checklists.md (User Documentation section)

6. Check _index.md was updated

7. Test examples with k6@master:
   Extract runnable examples (skip <!-- md-k6:skip --> blocks)
   For each example:
   - Write to /tmp/k6-test-<name>-<N>.js
   - Run: cd k6
   - Run: go run . run /tmp/k6-test-<name>-<N>.js
   - Report: SUCCESS or FAILURE with output
   - Clean up temp file

   CRITICAL: You MUST actually execute code examples.
   If ALL examples have skip markers: Status is ⚠️ UNTESTED (NOT ✅ PASS)

8. Report findings:
   ## Documentation Review: [FEATURE_NAME]
   **Status:** PASS / ISSUES FOUND
   **Commits:** [list]
   **Files Changed:** [list]
   **Visual Verification:** [results]
   **Link Validation:** [total/passed/failed with broken links list]
   **Example Tests:** [total/passed/failed/skipped with failures]
   **Content Checklist:** [each item]
   **Issues Found:** [list]
   **Recommendations:** [list]
```

## Release Notes Review Subagent

```
Review release notes for [FEATURE_NAME].

Branch: [BRANCH_NAME]
Locate k6 repository in current directory or subdirectories.

1. Checkout the branch:
   cd k6
   git fetch origin [BRANCH_NAME]
   git checkout [BRANCH_NAME]

2. Check what changed:
   git log origin/[BRANCH_NAME]..HEAD --oneline
   OR: git diff origin/[BRANCH_NAME] -- "release notes/"

3. Read the release notes file (release notes/v*.md)

4. Review against checklist in references/review-checklists.md (Release Notes section)

5. Report findings:
   ## Release Notes Review: [FEATURE_NAME]
   **Status:** PASS / ISSUES FOUND
   **Commits:** [list]
   **File Changed:** [release notes file]
   **Checklist Results:** [each item]
   **Issues Found:** [list]
   **Recommendations:** [list]
```
