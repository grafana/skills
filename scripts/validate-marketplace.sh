#!/usr/bin/env bash
# Validate marketplace manifests and their declared skill directories.

set -euo pipefail

MANIFESTS=(
  ".claude-plugin/marketplace.json"
  ".cursor-plugin/marketplace.json"
  ".agents-plugin/marketplace.json"
)
PRIMARY_MANIFEST="${MANIFESTS[0]}"

for manifest in "${MANIFESTS[@]}"; do
  echo "Validating JSON syntax: $manifest"
  jq empty "$manifest"
done

for manifest in "${MANIFESTS[@]:1}"; do
  if ! cmp -s "$PRIMARY_MANIFEST" "$manifest"; then
    echo "ERROR: $manifest differs from $PRIMARY_MANIFEST"
    diff -u "$PRIMARY_MANIFEST" "$manifest" || true
    exit 1
  fi
done
echo "Marketplace manifests are identical"

duplicate_paths=$(jq -r '.plugins[].skills[]' "$PRIMARY_MANIFEST" | sort | uniq -d)
if [ -n "$duplicate_paths" ]; then
  echo "ERROR: Duplicate skill paths in $PRIMARY_MANIFEST:"
  echo "$duplicate_paths"
  exit 1
fi

missing_paths=0
while IFS= read -r declared_path; do
  skill_path=${declared_path#./}
  if [ ! -f "$skill_path/SKILL.md" ]; then
    echo "ERROR: Marketplace skill path does not contain SKILL.md: $declared_path"
    missing_paths=$((missing_paths + 1))
  fi
done < <(jq -r '.plugins[].skills[]' "$PRIMARY_MANIFEST")

if [ "$missing_paths" -gt 0 ]; then
  exit 1
fi

skill_count=$(jq '[.plugins[].skills[]] | length' "$PRIMARY_MANIFEST")
echo "Validated $skill_count marketplace skill paths"
