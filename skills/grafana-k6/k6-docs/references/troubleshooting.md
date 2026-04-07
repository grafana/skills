# Troubleshooting Guide

Common issues and solutions when documenting k6 features.

## TypeScript Module Resolution

### Error: `Cannot find module 'k6/browser'`

**Cause:** You likely used `npm install` instead of `pnpm install`. The k6-DefinitelyTyped workspace requires pnpm to create proper symlinks for module resolution.

**Fix:**
```bash
cd k6-DefinitelyTyped
pnpm install -w --filter "{./types/k6}..."
```

The first command creates a symlink for `@types/k6` in `node_modules`, which is required for TypeScript module resolution during tests.

### Error: `dtslint is not found`

**Cause:** Missing workspace dependencies.

**Fix:**
```bash
cd k6-DefinitelyTyped
pnpm install -w --filter "{./types/k6}..."
```

Ensure you're using the `--filter` flag to install workspace dependencies correctly.

### Pre-existing Test Failures

**Issue:** The test suite shows errors unrelated to your changes.

**Context:** The k6-DefinitelyTyped test suite may have pre-existing failures. This is normal.

**Action:** Focus on ensuring your NEW types don't introduce ADDITIONAL errors. Compare test output before and after your changes.

## Locating Documentation Files

When testing documentation, files may not be on the current branch.

### Step 1: Check Local Branches

```bash
# Search for branches matching the feature name
git branch | grep -i <feature-name>

# Example:
git branch | grep -i waitforevent
```

### Step 2: Check Remote Branches

If not found locally:

```bash
# Fetch all remote branch info
git fetch --all

# Search remote branches
git branch -r | grep -i <feature-name>

# Example:
git branch -r | grep -i waitforevent
```

### Step 3: Checkout the Branch

Once found:

```bash
# For remote branches, fetch and create local branch in one command
git fetch origin <branch-name>:<branch-name>
git checkout <branch-name>

# Example:
git fetch origin add/page-waitForEvent:add/page-waitForEvent
git checkout add/page-waitForEvent
```

**⚠️ Common Mistake:** Don't run `git checkout origin/branch-name` directly. It creates a detached HEAD state. Always use the fetch command above to create a local tracking branch.

### Step 4: Checkout from PR Number

If given a PR number, use GitHub CLI:

```bash
gh pr checkout <PR_NUMBER>
```

This automatically creates the local branch and checks it out.

### Step 5: Verify Files

After checkout, confirm the documentation files exist:

```bash
# List all changed files in this branch vs main
git diff main --name-only
```

## Link Validation Issues

### Link Returns 404

**Common causes:**

1. **Wrong casing:** `consolemessage` vs `console-message`
1. **Missing hyphens:** `browsercontext` vs `browser-context`
1. **Wrong path structure:** Check actual file/folder names in docs directory

**Fix:**
```bash
# Check the actual file name in the docs
ls -la docs/sources/k6/next/javascript-api/k6-browser/

# Compare with your link path
```

### Can't Extract Links from Diff

**Issue:** The git diff + grep pipeline isn't finding links.

**Debug:**
```bash
# Step-by-step debugging
cd k6-docs

# 1. Check diff has content
git diff main -- docs/sources/k6/next/ | head -20

# 2. Check for added lines
git diff main -- docs/sources/k6/next/ | grep '^\+' | head -20

# 3. Check for URLs
git diff main -- docs/sources/k6/next/ | grep '^\+' | grep 'grafana.com'
```

## agent-browser Issues

### Installation Fails

If `npm install -g agent-browser` fails, check Node.js version:

```bash
node --version  # Should be 18.x or higher
```

Update Node.js if needed, then retry installation.

### Browser Not Installed

After installing agent-browser, install the browser:

```bash
agent-browser install
```

This downloads Chromium for agent-browser to use.

### Command Not Found After Install

Check PATH includes npm global bin directory:

```bash
npm config get prefix
# Should show a directory in your PATH
```

Add to PATH if needed (add to ~/.bashrc or ~/.zshrc):
```bash
export PATH="$(npm config get prefix)/bin:$PATH"
```

## k6 Testing Issues

### Error: `k6: command not found` when running `go run . run`

**Issue:** You're not in the k6 repository directory.

**Fix:**
```bash
# Navigate to k6 repo first
cd /path/to/k6

# Then run the command
go run . run /tmp/test-script.js
```

### Examples Work Locally But Not in Docs

**Issue:** Example has environment-specific code (hardcoded paths, local servers).

**Fix:** Ensure examples use:
- Generic URLs (use `https://quickpizza.grafana.com/` for HTTP examples)
- No hardcoded file paths
- No dependencies on local services unless documented

### k6 Branch Issues

**Issue:** Testing with wrong k6 version.

**Verify:**
```bash
cd /path/to/k6
git branch  # Should show * master
git status  # Should be clean or only local uncommitted changes
```

**IMPORTANT:** k6 must be on `master` branch for testing examples with new features.
