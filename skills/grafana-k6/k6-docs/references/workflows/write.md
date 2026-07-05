# Write Documentation Workflow

Document k6 features across three repositories: k6-DefinitelyTyped (TypeScript types), k6-docs (user documentation), and k6 (release notes).

## Before Starting

Ask the user for clarification if not already specified:

1. **PR or branch?** - Is there a PR number to fetch with `gh pr checkout <PR>`, or should you check out a branch directly?
1. **Which release?** - What milestone/version is this for? (e.g., `v1.5.0`)
   - Release branches are named `release-X.X.0` or `release-vX.X.0`
   - This format is used in both k6 and k6-DefinitelyTyped repositories
   - If documenting from a PR, **use the PR's milestone when it exists** to decide which doc version(s) get the change.
1. **Repository paths?** - Where are the repositories located? Auto-detect from `pwd` or ask user.

## Setup

- Determine absolute paths to repos before running commands
- For PR number: First `cd /absolute/path/to/repo`, then `gh pr checkout <PR>` (separate commands)
- For branch name: Use `${CLAUDE_PLUGIN_ROOT}/skills/k6-docs/scripts/find_branch.sh`
- k6 must be on `master` branch for testing examples
- Never chain commands with `&&` or `;` - run separately

## Workflow

Create tasks for each documentation type requested, and handle them using parallel subagents.

## 1. User Documentation (k6-docs)

**Base branch:** `main` (k6-docs always branches from main, targeting `docs/sources/k6/next/` for upcoming releases)

**Branch name:** `add/<feature-name>` (e.g., `add/page-waitForEvent`)

Steps:
1. Create `docs/sources/k6/next/javascript-api/<module>/<feature>.md`
1. Use [User documentation template](../templates/documentation.md)
1. Update `docs/sources/k6/next/javascript-api/<module>/_index.md` table
1. Add bidirectional cross-links to related methods (alphabetically sorted)

**Test (REQUIRED):**
```bash
# Start local server
cd k6-docs
npm install
npm start  # Runs at http://localhost:3002
```

Then follow [Documentation checklist](../checklists/documentation.md):
- Validate ALL links (git diff + grep + curl pipeline)
- Visual verification with agent-browser
- Test ALL examples with k6@master (see [Testing workflow](../testing-workflow.md))

**Commit format:**
```
docs: add <module>.<feature> documentation

Adds documentation for <brief description>.

Related: grafana/k6#<PR_NUMBER>
```

Example: `docs: add browser.page.waitForEvent documentation`

**Note:** `Related: grafana/k6#1234` format creates bidirectional GitHub links between repositories.

## 2. TypeScript Definitions (k6-DefinitelyTyped)

**Base branch:** `release-X.X.0` (TypeScript branches from release branch because types are published per k6 version)

**Branch name:** `add/<feature-name>` (e.g., `add/page-waitForEvent`)

Steps:
1. Identify the interface (Page, HTTP, etc.) - see [Repository structure guide](../repository-structure.md)
1. Add method signature to `types/k6/<module>/index.d.ts` - see [TypeScript patterns](../typescript-patterns.md)
1. Add type tests to `types/k6/test/<module>.ts`
1. Format: `${CLAUDE_PLUGIN_ROOT}/skills/k6-docs/scripts/format_typescript.sh`

**Test (REQUIRED):**
```bash
cd k6-DefinitelyTyped
pnpm install -w --filter "{./types/k6}..."
pnpm test k6
```

See [TypeScript checklist](../checklists/typescript.md) for full validation.

**Commit format:**
```
<module>: add TypeScript definitions for <feature>

<Brief description of what was added>

Related: grafana/k6#<PR_NUMBER>
```

Example: `browser: add TypeScript definitions for page.waitForEvent`

### Using Playwright Documentation as Reference

**For browser module only:** k6-browser's API is based on Playwright. Always reference official Playwright documentation to ensure API signatures, parameters, and patterns match established conventions.

```bash
# Search for Playwright documentation
WebSearch: "playwright page.waitForEvent documentation"

# Fetch specific Playwright docs page
WebFetch: url="https://playwright.dev/docs/api/class-page#page-wait-for-event"
         prompt="Explain the page.waitForEvent method parameters and usage"
```

**Note:** k6-browser may have slight differences from Playwright (e.g., different default timeouts, missing features). Always verify the actual k6 implementation, but use Playwright docs as your baseline reference.

## 3. Release Notes (k6)

**Branch:** `release-X.X.0` or `release-vX.X.0` (same repository, use existing release branch)

Steps:
1. Edit `release notes/v{VERSION}.md`
1. Use [Release notes template](../templates/release-notes.md)
1. Check PR commits for external contributors - see [k6 team members list](../k6-team-members.md)
   - Follow the 3-step identification process
   - Remember: Git shows real names, not GitHub handles
   - If team list is outdated, run `${CLAUDE_PLUGIN_ROOT}/skills/k6-docs/scripts/update_team_members.sh` to refresh
1. Thank external contributors: `Thanks, @username for your contribution! 🎉`

**Test examples (REQUIRED):**

Release note examples do NOT need `<!-- md-k6:skip -->` markers (they demonstrate features, not runnable tests). However, you should still verify they're syntactically correct and follow k6 patterns.

**Commit format:**
```
release notes: add <feature> to vX.X.0

Documents the new <feature> that allows <brief description>.

Related: #<PR_NUMBER>
```

Example: `release notes: add page.waitForEvent to v1.5.0`

**Note:** `Related: #1234` format (without repo prefix) because this is in the same repository as the PR.

## Verification

After completing all three, use [Review workflow](review.md) to validate the work.
