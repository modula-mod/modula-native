#!/bin/bash
# Cumulative N4B→N4G split from a recovery snapshot.
# Requires: already on a committed recovery snapshot that contains the full stack.
# Does not reset the original recovery ref.
set -euo pipefail

REPO="${1:-/Users/msjoy/Developer/modula-native}"
cd "$REPO"

BASE="${N4A_BASE:-1ef3fc42d60849a565a5655943861c16ca502431}"
SOURCE_REF="${SOURCE_REF:-HEAD}"

echo "Base N4A: $BASE"
echo "Source:   $(git rev-parse "$SOURCE_REF")"

if ! git merge-base --is-ancestor "$BASE" "$SOURCE_REF"; then
  echo "Source is not a descendant of N4A base $BASE" >&2
  exit 1
fi

# Phase branches follow staging docs + this agent suffix.
N4B="cursor/phase-n4b-ios-post-system-ac57"
N4C="cursor/phase-n4c-ios-social-expansion-ac57"
N4D="cursor/phase-n4d-ios-command-platform-ac57"
N4E="cursor/phase-n4e-ios-first-run-security-ac57"
N4F="cursor/phase-n4f-ios-creation-studio-ac57"
N4G="cursor/phase-n4g-ios-visual-language-ac57"

echo "This helper records intended branch names and stops before rewriting history."
echo "Hunk-level split of shared files must be done interactively from:"
echo "  docs/environment/n4c-remote-staging.md"
echo "  docs/environment/n4d-remote-staging.md"
echo "  docs/environment/n4e-remote-staging.md"
echo "  docs/environment/n4f-remote-staging.md"
echo "  docs/environment/n4g-remote-staging.md"
echo
echo "Target chain:"
echo "  $BASE"
echo "    -> $N4B"
echo "    -> $N4C"
echo "    -> $N4D"
echo "    -> $N4E"
echo "    -> $N4F"
echo "    -> $N4G"
echo
echo "Do not invent historical SHAs. Record them only after each compiling commit."
exit 0
