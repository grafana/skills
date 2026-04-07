#!/usr/bin/env bash
# Find and checkout a branch by feature name
# Usage: find_branch.sh <feature-name>

if [ -z "$1" ]; then
    echo "Usage: $0 <feature-name>"
    exit 1
fi

FEATURE="$1"

echo "Searching local branches..."
LOCAL_BRANCH=$(git branch | grep -iF "$FEATURE" | head -1 | tr -d ' *')

if [ -n "$LOCAL_BRANCH" ]; then
    echo "Found local branch: $LOCAL_BRANCH"
    git checkout "$LOCAL_BRANCH"
    exit 0
fi

echo "Searching remote branches..."
git fetch --all
REMOTE_BRANCH=$(git branch -r | grep -iF "$FEATURE" | head -1 | sed 's/.*origin\///' | tr -d ' ')

if [ -n "$REMOTE_BRANCH" ]; then
    echo "Found remote branch: $REMOTE_BRANCH"
    git fetch origin "$REMOTE_BRANCH:$REMOTE_BRANCH"
    git checkout "$REMOTE_BRANCH"
    exit 0
fi

echo "No branch found for: $FEATURE"
exit 1
