#!/usr/bin/env bash
# Format TypeScript definitions using dprint
# Usage: format_typescript.sh [path_to_k6_DefinitelyTyped]

REPO_PATH="${1:-.}"
cd "$REPO_PATH" || exit 1

echo "Formatting TypeScript files..."
pnpm dprint fmt types/k6/
