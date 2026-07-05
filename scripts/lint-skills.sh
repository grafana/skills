#!/usr/bin/env bash
# lint-skills.sh — Validates SKILL.md files against the Agent Skills standard.
#
# Checks performed:
#   1.  YAML frontmatter exists and closes properly
#   2.  Inline frontmatter scalars avoid unquoted YAML-breaking ": " sequences
#   3.  Required fields: name, description
#   4.  Name format: lowercase alphanumeric + hyphens, no leading/trailing/consecutive hyphens, max 64 chars
#   5.  Frontmatter name matches parent directory name (warning)
#   6.  Description is non-empty and ≤ 1024 characters
#   7.  Only known frontmatter fields are used (spec + Claude Code extensions)
#   8.  Boolean fields (user-invocable, disable-model-invocation) have valid values
#   9.  Compatibility field ≤ 500 characters (if present)
#   10. Skill body is non-empty and starts with a markdown heading
#   11. Line count warning if over 500 lines (per repo guidelines)
#   12. Description trigger phrase check ("Use when")
#   13. Scripts in skills/*/scripts/ are executable
#   14. Supply chain security: unpinned package/image versions in code examples
#
# Usage:
#   ./scripts/lint-skills.sh [directory ...]
#   When called without arguments, scans all conventional skill locations
#   aligned with the npx skills CLI (vercel-labs/skills) and Agent Skills standard.

set -euo pipefail

# --- Conventional skill directories ---
# Full list aligned with npx skills CLI discovery (vercel-labs/skills).
# See: https://github.com/vercel-labs/skills#skill-discovery
CONVENTIONAL_DIRS="
  skills
  skills/.curated
  skills/.experimental
  skills/.system
  plugins
  .agents/skills
  .agent/skills
  .augment/skills
  .claude/skills
  .codebuddy/skills
  .commandcode/skills
  .continue/skills
  .cortex/skills
  .crush/skills
  .factory/skills
  .goose/skills
  .junie/skills
  .iflow/skills
  .kilocode/skills
  .kiro/skills
  .kode/skills
  .mcpjam/skills
  .vibe/skills
  .mux/skills
  .openhands/skills
  .pi/skills
  .qoder/skills
  .qwen/skills
  .roo/skills
  .trae/skills
  .windsurf/skills
  .zencoder/skills
  .neovate/skills
  .pochi/skills
  .adal/skills
"

# --- Resolve search directories ---
SEARCH_DIRS=""
if [ $# -gt 0 ]; then
  SEARCH_DIRS="$*"
else
  # Auto-detect: use only conventional dirs that exist
  for dir in $CONVENTIONAL_DIRS; do
    if [ -d "$dir" ]; then
      SEARCH_DIRS="$SEARCH_DIRS $dir"
    fi
  done
  SEARCH_DIRS=$(echo "$SEARCH_DIRS" | xargs)  # trim whitespace
fi

if [ -z "$SEARCH_DIRS" ]; then
  echo "No skill directories found. Looked for: $CONVENTIONAL_DIRS"
  echo "Pass directories explicitly: ./lint-skills.sh <dir> [dir ...]"
  exit 1
fi

ERRORS=0
WARNINGS=0

# Agent Skills spec fields: name, description, license, compatibility, metadata, allowed-tools
# Claude Code extension fields: user-invocable, disable-model-invocation, argument-hint
KNOWN_FIELDS="name description license compatibility metadata allowed-tools user-invocable disable-model-invocation argument-hint"

red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }

error() {
  red "  ERROR: $1"
  ERRORS=$((ERRORS + 1))
}

warn() {
  yellow "  WARN:  $1"
  WARNINGS=$((WARNINGS + 1))
}

ok() {
  printf '  ✓ %s\n' "$1"
}

# --- Find all SKILL.md files across all search directories ---
SKILL_FILES=""
for dir in $SEARCH_DIRS; do
  if [ -d "$dir" ]; then
    found=$(find "$dir" -name "SKILL.md" -type f | sort)
    if [ -n "$found" ]; then
      SKILL_FILES="$SKILL_FILES
$found"
    fi
  else
    yellow "Directory not found, skipping: $dir"
  fi
done
SKILL_FILES=$(echo "$SKILL_FILES" | sed '/^$/d' | sort -u)
SKILL_COUNT=$(echo "$SKILL_FILES" | wc -l | tr -d ' ')

if [ -z "$SKILL_FILES" ]; then
  red "No SKILL.md files found in: $SEARCH_DIRS"
  exit 1
fi

echo "Linting $SKILL_COUNT skill(s) in: $SEARCH_DIRS"
echo ""

for skill in $SKILL_FILES; do
  echo "--- $skill"

  # ------------------------------------------------------------------
  # 1. Frontmatter exists and closes properly
  # ------------------------------------------------------------------
  first_line=$(head -1 "$skill")
  if [ "$first_line" != "---" ]; then
    error "Missing opening YAML frontmatter delimiter (---)"
    continue  # Can't parse further without frontmatter
  fi

  # Find the closing delimiter (second occurrence of ---)
  closing_line=$(awk 'NR>1 && /^---$/{print NR; exit}' "$skill")
  if [ -z "$closing_line" ]; then
    error "Missing closing YAML frontmatter delimiter (---)"
    continue
  fi
  ok "Frontmatter structure"

  # Extract frontmatter (between the two --- lines, exclusive)
  frontmatter=$(awk "NR>1 && NR<$closing_line" "$skill")

  # Catch the common YAML failure mode for inline plain scalars: an unquoted
  # ": " sequence inside the value is parsed as a mapping separator.
  plain_scalar_errors=$(printf '%s\n' "$frontmatter" | awk '
    /^[^[:space:]#][^:]*:[[:space:]]*/ {
      field = $0
      sub(/:.*/, "", field)

      value = $0
      sub(/^[^:]*:[[:space:]]*/, "", value)

      if (value == "" || value ~ /^[>|][+-]?[[:space:]]*(#.*)?$/) next

      first = substr(value, 1, 1)
      if (first == "\"" || first == sprintf("%c", 39)) next

      if (value ~ /:[[:space:]]/) {
        printf "%d:%s\n", NR + 1, field
      }
    }
  ')
  if [ -n "$plain_scalar_errors" ]; then
    while IFS=: read -r line field; do
      error "Invalid inline YAML scalar at line $line ('$field'): quote values containing ': ' or use a block scalar"
    done <<< "$plain_scalar_errors"
    continue
  fi
  ok "Inline frontmatter scalars"

  # ------------------------------------------------------------------
  # 3. Required fields: name, description
  # ------------------------------------------------------------------
  skill_name=$(echo "$frontmatter" | awk '/^name:/{print $2; exit}')
  if [ -z "$skill_name" ]; then
    error "Missing required 'name' field in frontmatter"
  else
    ok "Has 'name' field: $skill_name"

    # ------------------------------------------------------------------
    # 3b. Name format validation (Agent Skills spec)
    #     - Max 64 chars, lowercase alphanumeric + hyphens only
    #     - Must not start or end with hyphen
    #     - Must not contain consecutive hyphens (--)
    # ------------------------------------------------------------------
    name_len=${#skill_name}
    if [ "$name_len" -gt 64 ]; then
      error "'name' exceeds 64 characters ($name_len)"
    fi
    if echo "$skill_name" | grep -qE '[^a-z0-9-]'; then
      error "'name' contains invalid characters (must be lowercase a-z, 0-9, hyphens only): '$skill_name'"
    fi
    if echo "$skill_name" | grep -qE '^-|-$'; then
      error "'name' must not start or end with a hyphen: '$skill_name'"
    fi
    if echo "$skill_name" | grep -q -- '--'; then
      error "'name' must not contain consecutive hyphens (--): '$skill_name'"
    fi
  fi

  has_description=$(echo "$frontmatter" | grep -c "^description:" || true)
  if [ "$has_description" -eq 0 ]; then
    error "Missing required 'description' field in frontmatter"
  else
    # Check description is non-empty (handle inline, >, |, and plain block styles)
    desc_value=$(echo "$frontmatter" | awk '/^description:/{
      sub(/^description:[[:space:]]*/, "");
      if ($0 != "" && $0 != ">" && $0 != "|") { print $0; exit }
    }')
    # For multiline descriptions (>, |, or plain block with indented continuation)
    if [ -z "$desc_value" ]; then
      desc_value=$(echo "$frontmatter" | awk '/^description:/{found=1; next}
        found && /^[[:space:]]+[^[:space:]]/{gsub(/^[[:space:]]+/, ""); print; exit}
        found && /^[^[:space:]]/{exit}')
    fi
    if [ -z "$desc_value" ]; then
      error "'description' field is empty"
    else
      ok "Has 'description' field"
    fi

    # ------------------------------------------------------------------
    # 3c. Description length validation (max 1024 chars per spec)
    # ------------------------------------------------------------------
    full_desc_text=$(echo "$frontmatter" | awk '/^description:/{found=1; sub(/^description:[[:space:]]*/, ""); if ($0 != ">" && $0 != "|") buf=$0; next}
      found && /^[[:space:]]+[^[:space:]]/{gsub(/^[[:space:]]+/, ""); buf=buf " " $0; next}
      found && /^[^[:space:]]/{exit}
      END{print buf}')
    desc_len=${#full_desc_text}
    if [ "$desc_len" -gt 1024 ]; then
      warn "'description' exceeds 1024 characters ($desc_len) — spec recommends max 1024"
    fi
  fi

  # ------------------------------------------------------------------
  # 3. Name matches directory name
  # ------------------------------------------------------------------
  if [ -n "$skill_name" ]; then
    dir_name=$(basename "$(dirname "$skill")")
    if [ "$dir_name" != "$skill_name" ]; then
      warn "Frontmatter name '$skill_name' does not match directory name '$dir_name'"
    else
      ok "Name matches directory"
    fi
  fi

  # ------------------------------------------------------------------
  # 4. Only known frontmatter fields
  # ------------------------------------------------------------------
  field_names=$(echo "$frontmatter" | grep -E "^[a-z]" | awk -F: '{print $1}')
  unknown_found=0
  for field in $field_names; do
    is_known=0
    for known in $KNOWN_FIELDS; do
      if [ "$field" = "$known" ]; then
        is_known=1
        break
      fi
    done
    if [ "$is_known" -eq 0 ]; then
      warn "Unknown frontmatter field: '$field'"
      unknown_found=1
    fi
  done
  if [ "$unknown_found" -eq 0 ]; then
    ok "All frontmatter fields are known"
  fi

  # ------------------------------------------------------------------
  # 5. Boolean field validation
  # ------------------------------------------------------------------
  for bool_field in "user-invocable" "disable-model-invocation"; do
    bool_value=$(echo "$frontmatter" | awk -v f="$bool_field" '$0 ~ "^"f":"{print $2; exit}')
    if [ -n "$bool_value" ]; then
      if [ "$bool_value" != "true" ] && [ "$bool_value" != "false" ]; then
        error "'$bool_field' must be 'true' or 'false', got '$bool_value'"
      else
        ok "'$bool_field' is valid: $bool_value"
      fi
    fi
  done

  # ------------------------------------------------------------------
  # 5b. Compatibility field length (max 500 chars per spec)
  # ------------------------------------------------------------------
  compat_value=$(echo "$frontmatter" | awk '/^compatibility:/{
    sub(/^compatibility:[[:space:]]*/, "");
    if ($0 != "" && $0 != ">" && $0 != "|") { print $0; exit }
  }')
  if [ -z "$compat_value" ]; then
    compat_value=$(echo "$frontmatter" | awk '/^compatibility:/{found=1; next}
      found && /^[[:space:]]+[^[:space:]]/{gsub(/^[[:space:]]+/, ""); buf=buf " " $0; next}
      found && /^[^[:space:]]/{exit}
      END{print buf}')
  fi
  if [ -n "$compat_value" ]; then
    compat_len=${#compat_value}
    if [ "$compat_len" -gt 500 ]; then
      warn "'compatibility' exceeds 500 characters ($compat_len) — spec recommends max 500"
    else
      ok "'compatibility' length: $compat_len"
    fi
  fi

  # ------------------------------------------------------------------
  # 6. Body checks: non-empty, starts with heading
  # ------------------------------------------------------------------
  first_content_line=$(awk "NR>$closing_line && /^[^[:space:]]/{print; exit}" "$skill")

  if [ -z "$first_content_line" ]; then
    error "Skill body is empty (no content after frontmatter)"
  else
    if ! echo "$first_content_line" | grep -q "^#"; then
      warn "Skill body does not start with a markdown heading"
    else
      ok "Body starts with heading"
    fi
  fi

  # ------------------------------------------------------------------
  # 7. Line count check (warn over 500)
  # ------------------------------------------------------------------
  total_lines=$(wc -l < "$skill" | tr -d ' ')
  if [ "$total_lines" -gt 500 ]; then
    warn "Skill is $total_lines lines (guideline: keep under 500)"
  else
    ok "Line count: $total_lines"
  fi

  # ------------------------------------------------------------------
  # 8. Description trigger phrase check
  # ------------------------------------------------------------------
  full_desc=$(echo "$frontmatter" | awk '/^description:/{found=1}
    found && /^[a-z]/ && !/^description:/{exit}
    found{print}')
  if [ -n "$full_desc" ]; then
    if ! echo "$full_desc" | grep -qi "use when"; then
      warn "Description missing 'Use when' trigger phrase (helps agent auto-loading)"
    fi
  fi

  # ------------------------------------------------------------------
  # 14. Supply chain security: unpinned package/image versions
  # ------------------------------------------------------------------
  skill_body=$(awk "NR>$closing_line" "$skill")

  # Extract lines inside dockerfile code fences (```dockerfile or ```Dockerfile),
  # allowing leading indentation for fenced blocks nested in markdown lists.
  # This avoids matching SQL FROM clauses and other non-Docker content.
  dockerfile_body=$(echo "$skill_body" | awk '
    /^[[:space:]]*```[Dd]ockerfile/{in_block=1; next}
    in_block && /^[[:space:]]*```/{in_block=0; next}
    in_block{print}
  ')

  if [ -n "$dockerfile_body" ]; then
    # Docker FROM with :latest tag
    # Handles optional flags before the image: FROM --platform=$BUILDPLATFORM alpine:latest
    # Uses POSIX [[:space:]] rather than \s so the regex works under any
    # POSIX-compliant grep (not just GNU grep's extensions).
    if echo "$dockerfile_body" | grep -qiE '^[[:space:]]*FROM([[:space:]]+--[^[:space:]]+)*[[:space:]]+[^[:space:]]+:latest([[:space:]]+AS[[:space:]]+[^[:space:]]+)?[[:space:]]*$'; then
      error "Dockerfile uses ':latest' tag — pin to a specific version (e.g. alpine:3.21) to prevent supply chain attacks"
    fi

    # Docker FROM with no version tag and no digest (@sha256:...)
    # Matches: FROM alpine  /  FROM ubuntu AS builder  /  FROM --platform=linux/amd64 alpine
    # Skips:   FROM node:18  /  FROM img@sha256:...  /  FROM scratch (legitimate special keyword)
    if echo "$dockerfile_body" | grep -vE '^[[:space:]]*FROM([[:space:]]+--[^[:space:]]+)*[[:space:]]+scratch([[:space:]]+AS[[:space:]]+[^[:space:]]+)?[[:space:]]*$' | \
         grep -qE '^[[:space:]]*FROM([[:space:]]+--[^[:space:]]+)*[[:space:]]+[a-zA-Z][^:@[:space:]]*([[:space:]]+AS[[:space:]]+[[:alnum:]_-]+)?[[:space:]]*$'; then
      error "Dockerfile FROM with no version tag — pin to a specific version (e.g. FROM alpine:3.21)"
    fi
  fi

  # npm install -g / --global without a pinned version (@x.y.z or @$(npm view ... version))
  if echo "$skill_body" | grep -E 'npm install (-g|--global) ' | grep -qvE '@([0-9]|\$\()'; then
    if echo "$skill_body" | grep -qE 'npm install (-g|--global) '; then
      error "npm global install without pinned version — use 'npm install -g pkg@x.y.z' to prevent supply chain attacks"
    fi
  fi

  # pip install <package> without a version specifier.
  # Validates each package token individually so that a mixed command like
  # "pip install pyyaml requests==2.31.0" still warns for the unpinned token.
  # Skips: -r / --requirement (installs from a file).
  # Skips known options that consume a separate value token (e.g. -c, --index-url).
  pip_install_unpinned=$(echo "$skill_body" | awk '
    /pip[0-9]?[[:space:]]+install[[:space:]]/ {
      line = $0
      sub(/^.*pip[0-9]?[[:space:]]+install[[:space:]]+/, "", line)
      # Stop at the first inline-code closing backtick so narrative text after
      # `pip install pkg==1.0` doesn'\''t get parsed as more packages.
      sub(/`.*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == "") next

      n = split(line, tokens, /[[:space:]]+/)
      skip_next = 0
      for (i = 1; i <= n; i++) {
        token = tokens[i]
        if (token == "") continue

        if (skip_next) { skip_next = 0; continue }

        # -r / --requirement: skip the whole line (requirements-file install)
        if (token == "-r" || token == "--requirement") next
        if (token ~ /^--requirement=/) next

        # Options that take a separate value token — skip the value
        if (token ~ /^(-c|--constraint|-i|--index-url|--extra-index-url|-f|--find-links|--trusted-host|-t|--target|--prefix|--root|--src|--log|--proxy|--timeout|--retries|--cert|--client-cert|--cache-dir|--build-option|--global-option|--no-binary|--only-binary|--progress-bar|--report)$/) {
          skip_next = 1; continue
        }

        # Skip all other flag tokens (valueless flags like -U, --upgrade, --user, --no-cache-dir)
        if (token ~ /^-/) continue

        # Warn if this package-like token lacks a version specifier
        if (token ~ /^[[:alnum:]_.-]+(\[[^]]+\])?([<>=!~].*)?$/ && token !~ /(==|>=|~=|<=|!=|>|<)/) {
          print token
        }
      }
    }
  ')
  if [ -n "$pip_install_unpinned" ]; then
    error "pip install without pinned version — use 'pip install pkg==x.y.z' to prevent supply chain attacks"
  fi

  # helm install / helm upgrade without --version
  # Join continuation lines (\-terminated) into single logical lines before checking,
  # so that --version on a follow-up line is not missed.
  helm_joined=$(echo "$skill_body" | awk '{
    if (/\\$/) { sub(/\\$/, ""); printf "%s ", $0 }
    else { print }
  }')
  if echo "$helm_joined" | grep -E 'helm (install|upgrade)' | grep -qv -- '--version'; then
    if echo "$helm_joined" | grep -qE 'helm (install|upgrade)'; then
      error "helm install/upgrade without --version — pin the chart version for reproducible deployments"
    fi
  fi

  echo ""
done

# --- Check script permissions ---
echo "--- Checking script permissions"
SCRIPT_FILES=""
for dir in $SEARCH_DIRS; do
  if [ -d "$dir" ]; then
    found=$(find "$dir" -path "*/scripts/*" -type f \( -name "*.sh" -o -name "*.py" -o ! -name "*.*" \) | sort)
    if [ -n "$found" ]; then
      SCRIPT_FILES="$SCRIPT_FILES
$found"
    fi
  fi
done
SCRIPT_FILES=$(echo "$SCRIPT_FILES" | sed '/^$/d' | sort -u)
if [ -n "$SCRIPT_FILES" ]; then
  for script_file in $SCRIPT_FILES; do
    if [ ! -x "$script_file" ]; then
      warn "Script is not executable: $script_file"
    fi
  done
  EXEC_COUNT=$(echo "$SCRIPT_FILES" | wc -l | tr -d ' ')
  ok "Checked $EXEC_COUNT script file(s)"
else
  ok "No script files found"
fi

echo ""
echo "=== Lint Summary ==="
echo "Skills:   $SKILL_COUNT"
echo "Errors:   $ERRORS"
echo "Warnings: $WARNINGS"

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  red "Linting failed with $ERRORS error(s)"
  exit 1
fi

if [ "$WARNINGS" -gt 0 ]; then
  echo ""
  yellow "Linting passed with $WARNINGS warning(s)"
else
  echo ""
  green "All checks passed"
fi
