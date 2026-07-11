#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"

if ! git -C "$REPO" remote get-url origin >/dev/null 2>&1; then
    echo "No 'origin' remote configured. Skipping sync check."
    exit 0
fi

git -C "$REPO" fetch --tags --prune origin 2>&1
STATUS=$(git -C "$REPO" status --short --branch)
echo "$STATUS"

if echo "$STATUS" | grep -q "behind"; then
    echo "It's out of sync with the remote. Please run 'git pull'."
fi
