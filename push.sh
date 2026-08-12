#!/usr/bin/env bash
# Commit all changes and push, auto-recovering from the read-only-account 403.
# Usage: ./push.sh "your commit message"
set -euo pipefail
cd "$(dirname "$0")"

MSG="${1:-}"
if [ -z "$MSG" ]; then echo "usage: ./push.sh \"commit message\""; exit 1; fi

if [ -z "$(git status --porcelain)" ]; then
  echo "Nothing to commit. Pushing any unpushed commits…"
else
  git add -A
  git -c user.name="Jason Miles" -c user.email="jason.miles@databricks.com" commit -m "$MSG"
fi

# First attempt.
if git push; then
  echo "✓ pushed"; exit 0
fi

# 403 fallback: git grabbed the read-only jason-miles_data token. Fix + retry.
echo "→ push failed; switching to jason-miles account and retrying…"
gh auth switch --user jason-miles >/dev/null 2>&1 || true
printf "protocol=https\nhost=github.com\n\n" | git credential-osxkeychain erase >/dev/null 2>&1 || true
gh auth setup-git >/dev/null 2>&1 || true
git push && echo "✓ pushed (after account fix)"
