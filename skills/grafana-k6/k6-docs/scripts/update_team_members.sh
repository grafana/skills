#!/usr/bin/env bash
# Update k6 team members list from GitHub API
# Usage: update_team_members.sh [output-file]

set -e

# Resolve default output file relative to the skill directory (one level above scripts/)
if [ -n "$1" ]; then
    OUTPUT_FILE="$1"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    OUTPUT_FILE="${SCRIPT_DIR}/references/k6-team-members.md"
fi

echo "Fetching k6 team members from GitHub..."

# Fetch all members of grafana/k6 repository collaborators with push+ access
# This gets people who have write/admin access to the k6 repo
MEMBERS=$(gh api repos/grafana/k6/collaborators \
    --paginate \
    --slurp \
    --jq '[.[][] | select(.permissions.push == true or .permissions.admin == true) | {login: .login, name: .name}] | sort_by(.login | ascii_downcase)')

# Start building the markdown file
cat > "$OUTPUT_FILE" <<'EOF'
# Grafana k6 Team Members

Do NOT thank these people as external contributors in release notes:

| GitHub Handle          | Name                    |
| ---------------------- | ----------------------- |
EOF

# Add each member to the table
echo "$MEMBERS" | jq -r '.[] | "| \(.login) | \(.name // .login) |"' >> "$OUTPUT_FILE"

echo ""
echo "✓ Updated $OUTPUT_FILE with $(echo "$MEMBERS" | jq 'length') team members"

# Show a preview
echo ""
echo "Preview (first 10 members):"
head -15 "$OUTPUT_FILE" | tail -10
