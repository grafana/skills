#!/usr/bin/env bash
# Validate all documentation links in k6-docs branch
# Usage: validate_links.sh <docs-repo-path>

if [ -z "$1" ]; then
    echo "Usage: $0 <docs-repo-path>"
    exit 1
fi

DOCS_PATH="$1"
cd "$DOCS_PATH" || exit 1

echo "Extracting new links from git diff..."
LINKS=$(git diff main -- docs/sources/k6/next/ | grep '^\+' | grep -oE 'https://grafana\.com/docs/k6/<K6_VERSION>/[^)\"]+' | sed 's/<K6_VERSION>/next/g' | sort -u)

if [ -z "$LINKS" ]; then
    echo "No new links found"
    exit 0
fi

echo "Checking links against local server (http://localhost:3002)..."
echo ""

FAILED=0
PASSED=0

while IFS= read -r link; do
    # Convert grafana.com link to localhost
    LOCAL_URL=$(echo "$link" | sed 's|https://grafana.com|http://localhost:3002|')

    STATUS=$(curl --connect-timeout 5 --max-time 10 -s -o /dev/null -w '%{http_code}' "$LOCAL_URL")

    if [ "$STATUS" = "200" ]; then
        echo "✓ $LOCAL_URL"
        ((PASSED++))
    else
        echo "✗ $LOCAL_URL (HTTP $STATUS)"
        ((FAILED++))
    fi
done <<< "$LINKS"

echo ""
echo "Results: $PASSED passed, $FAILED failed"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

exit 0
