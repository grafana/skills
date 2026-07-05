# agent-browser Command Reference

agent-browser is the PRIMARY tool for visual verification of documentation. Use it to catch rendering issues, broken styles, and visual problems that HTTP status checks cannot detect.

## Installation

Check if installed:
```bash
which agent-browser
```

If not installed:
```bash
npm install -g agent-browser
agent-browser install
```

## Navigation

- `agent-browser open <url>` - Navigate to URL
- `agent-browser back` - Go back in history
- `agent-browser reload` - Reload current page

## Inspection

- `agent-browser snapshot` - Get accessibility tree with element @refs
- `agent-browser snapshot -i` - Interactive elements only
- `agent-browser screenshot [path]` - Screenshot (add `--full` for full page)
- `agent-browser get text <selector>` - Get element text
- `agent-browser get title` - Get page title
- `agent-browser get url` - Get current URL

## Interaction

- `agent-browser click <selector|@ref>` - Click element
- `agent-browser type <selector> <text>` - Type into element
- `agent-browser scroll <up|down|left|right> [pixels]` - Scroll page
- `agent-browser wait <selector|milliseconds>` - Wait for element or time

## Selectors

Two types of selectors:

**CSS selectors:**
- `"a[href*='waitforrequest']"` - Links containing text
- `".docs-table td"` - Table cells with class
- `"h1"` - Headers

**@refs from snapshot:**
- Use `snapshot` command first to get element @refs
- Example: `@e42` references a specific element
- More reliable than CSS selectors

## Sessions

- `--session <name>` - Use isolated browser session
- Default session persists between commands

## Tips

- **Always use `--full` flag** for full-page screenshots when verifying docs
- **Use `snapshot` to find elements** before clicking (provides @refs)
- **Combine with pipes:** `agent-browser get text .title | grep "Error"` to check for issues
- Check for 404s: `agent-browser get title` should not return "404" or "Page Not Found"

## Example Verification Workflow

```bash
# Step 1: Navigate to module index
agent-browser open "http://localhost:3002/docs/k6/next/javascript-api/k6-browser/page/"

# Step 2: Verify method appears in table
agent-browser screenshot --full index-page.png

# Step 3: Navigate to method docs
agent-browser open "http://localhost:3002/docs/k6/next/javascript-api/k6-browser/page/waitforevent/"

# Step 4: Verify rendering
agent-browser screenshot --full method-page.png

# Step 5: Check related links
agent-browser snapshot > snapshot.txt
agent-browser click "a[href*='waitforrequest']"
agent-browser screenshot related-link.png

# Step 6: Verify no 404
agent-browser get title  # Should not be "404" or "Page Not Found"
```

## Fallback: curl

If agent-browser is unavailable, use `curl` as a last resort (provides no visual verification):

```bash
# Check HTTP status only
curl -s -o /dev/null -w '%{http_code}' http://localhost:3002/docs/k6/next/path/
```

**Note:** curl only verifies pages return 200 - it cannot catch rendering, styling, or visual issues.
