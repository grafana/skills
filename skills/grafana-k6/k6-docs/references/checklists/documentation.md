# User Documentation Checklist

## Front Matter

- [ ] title matches method signature format
- [ ] description is accurate

## Parameters Table

- [ ] All parameters documented with Type, Default, Description
- [ ] Required params marked as "Required."

## Returns Section

- [ ] Return type is accurate
- [ ] Description is clear

## Examples

**REQUIRED:** Test ALL examples with k6@master. See [Testing workflow](../testing-workflow.md) for complete procedure.

```bash
# Extract example from docs
# Write to /tmp/test-example.js
# Then run:
cd /path/to/k6
go run . run /tmp/test-example.js
```

**Checklist:**
- [ ] Code is complete and runnable
- [ ] Includes proper imports
- [ ] Non-runnable code has `<!-- md-k6:skip -->` comment
- [ ] All runnable examples tested with k6@master
- [ ] All examples pass without errors
- [ ] Examples use generic URLs (not localhost or hardcoded paths)

## Best Practices

- [ ] Uses 1. for ALL numbered list items (not 1., 2., 3.)
- [ ] Helpful and actionable

## Related Section

- [ ] Links sorted ALPHABETICALLY
- [ ] Bidirectional links exist (if A links to B, B links to A)

## Links

**REQUIRED:** Validate ALL added links using this procedure:

### Step 1: Extract Links from Changes

```bash
cd k6-docs
git diff main -- docs/sources/k6/next/ | grep '^\+' | grep -oE 'https://grafana\.com/docs/k6/<K6_VERSION>/[^)\"]+' | sed 's/<K6_VERSION>/next/g' | sort -u
```

This extracts only YOUR added links, not pre-existing ones.

### Step 2: Check Each Link

For each URL from step 1, replace `https://grafana.com` with `http://localhost:3002` and verify:

```bash
# Check multiple links at once
for url in \
  "/docs/k6/next/javascript-api/k6-browser/page/waitforevent/" \
  "/docs/k6/next/javascript-api/k6-browser/request/"
do
  echo "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3002$url) $url"
done
```

All links must return `200`. Any `404` is a broken link that must be fixed.

### Step 3: Fix Broken Links

Common link issues:
- **Wrong casing:** `consolemessage` vs `console-message`
- **Missing hyphens:** `browsercontext` vs `browser-context`
- **Wrong path:** Check actual file/folder names in docs directory

### Step 4: Re-validate After Fixes

Run validation again to ensure all links return `200`.

**Checklist:**
- [ ] All links extracted with git diff pipeline
- [ ] Each link checked with curl against localhost:3002
- [ ] All links return 200 (no 404s)
- [ ] Broken links fixed and re-validated

## Visual Verification

**REQUIRED:** Use agent-browser to verify rendering. Screenshots catch issues HTTP 200 status cannot detect.

When reviewing screenshots, verify ALL seven criteria:

1. **No 404 errors** - Page content renders, not an error page
1. **Parameters table** - All columns visible (Parameter, Type, Default, Description)
1. **Code blocks** - Syntax highlighting applied (colored keywords)
1. **Navigation** - Breadcrumbs show correct path (e.g., "k6 > JavaScript API > k6-browser > Page > waitForEvent")
1. **Related links section** - Links are styled and clickable
1. **No broken images** - All images load properly
1. **Proper formatting** - Headers, lists, and tables render correctly

**Commands:**
```bash
# Take full-page screenshot (ALWAYS use --full flag for docs)
agent-browser screenshot --full page.png

# Check page title (should not be "404")
agent-browser get title

# Verify related links work
agent-browser snapshot  # Get @refs
agent-browser click "@e42"  # Click link by @ref
```

See [agent-browser reference](../agent-browser-reference.md) for complete command list.

**Checklist:**
- [ ] Method appears in module's API index table (screenshot verified)
- [ ] Method documentation page loads without 404 (screenshot verified)
- [ ] Parameters table renders with all columns (screenshot verified)
- [ ] Code examples render with syntax highlighting (screenshot verified)
- [ ] Related links are clickable and load correct pages (click and screenshot each)
- [ ] Navigation breadcrumbs are correct (screenshot verified)
- [ ] No broken images or formatting issues (screenshot verified)

## Index

- [ ] _index.md updated with new method entry
- [ ] New method row is in **alphabetical order** in the method table
