#!/bin/bash
# N4 closeout recovery snapshot.
# Never: git reset --hard, git clean, git restore, git checkout --, git stash
set -euo pipefail

REPO="${1:-/Users/msjoy/Developer/modula-native}"
cd "$REPO"

echo "===== inspect ====="
git status -sb
git branch --show-current
git rev-parse HEAD
git rev-parse origin/main || true
git log --graph --decorate --oneline --all -20
git diff --stat

STAMP="$(date +%Y%m%d-%H%M%S)"
RECOVERY_BRANCH="recovery/n4-source-stack-$STAMP"
echo "===== switch $RECOVERY_BRANCH ====="
git switch -c "$RECOVERY_BRANCH"

git add -A

# Keep local-only / secret / generated paths out of the snapshot.
git restore --staged -- \
  ".cursor/hooks/state" \
  2>/dev/null || true

# Unstage ignored-class leftovers if they slipped through.
git diff --cached --name-only | while IFS= read -r path; do
  case "$path" in
    .cursor/hooks/state/*|DerivedData/*|build/*|*.xcuserstate|*.p12|*.mobileprovision|*.pem|*.key|.env|.env.*|*.local)
      git restore --staged -- "$path" || true
      ;;
  esac
done

echo "===== staged ====="
git status
git diff --cached --stat

git commit -m "chore(recovery): checkpoint N4B-N4G source stack"

git branch recovery/n4-stack-snapshot HEAD

echo "RECOVERY_HEAD=$(git rev-parse HEAD)"
echo "RECOVERY_BRANCH=$RECOVERY_BRANCH"
echo "SNAPSHOT_REF=recovery/n4-stack-snapshot"
