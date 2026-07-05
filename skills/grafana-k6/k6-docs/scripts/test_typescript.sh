#!/usr/bin/env bash
# Test TypeScript definitions in k6-DefinitelyTyped
# Usage: test_typescript.sh [path_to_k6_DefinitelyTyped]

REPO_PATH="${1:-.}"
cd "$REPO_PATH" || exit 1

echo "Installing dependencies..."
pnpm install -w --filter "{./types/k6}..."

echo "Running TypeScript tests..."
pnpm test k6
