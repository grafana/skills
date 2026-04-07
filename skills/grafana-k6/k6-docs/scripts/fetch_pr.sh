#!/usr/bin/env bash
# Fetch and checkout a PR in the current repository
# Usage: fetch_pr.sh <PR_NUMBER>

if [ -z "$1" ]; then
    echo "Usage: $0 <PR_NUMBER>"
    exit 1
fi

gh pr checkout "$1"
