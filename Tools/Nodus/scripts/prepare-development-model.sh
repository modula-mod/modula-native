#!/bin/sh
set -eu

NODUS_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TRACKED_MANIFEST="$NODUS_ROOT/manifests/nodus-r7-experimental.json"
CACHE_ROOT="${MODULA_DEVELOPER_MODEL_CACHE:-$HOME/Library/Application Support/Modula/DeveloperModels/Nodus/R7}"
DESTINATION="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?UNLOCALIZED_RESOURCES_FOLDER_PATH is required}/Nodus/R7"
REQUIRED="${MODULA_REQUIRE_EXPERIMENTAL_NODUS:-0}"
INCLUDE="${MODULA_INCLUDE_EXPERIMENTAL_NODUS:-}"

if [ -z "$INCLUDE" ]; then
  if [ "${CONFIGURATION:-}" = "Debug" ]; then INCLUDE=1; else INCLUDE=0; fi
fi

if [ "$INCLUDE" != "1" ]; then
  rm -rf "$DESTINATION"
  echo "Nodus R7 experimental bundling disabled for ${CONFIGURATION:-unknown}"
  exit 0
fi

if [ ! -d "$CACHE_ROOT" ]; then
  rm -rf "$DESTINATION"
  if [ "$REQUIRED" = "1" ]; then
    echo "error: required Nodus R7 developer cache is missing: $CACHE_ROOT" >&2
    exit 1
  fi
  echo "warning: Nodus R7 developer cache is absent; building with modelNotInstalled" >&2
  exit 0
fi

/usr/bin/python3 "$NODUS_ROOT/scripts/verify_development_model.py" \
  --manifest "$TRACKED_MANIFEST" \
  --model-directory "$CACHE_ROOT"

if [ -f "$DESTINATION/nodus-r7-experimental.json" ] \
  && cmp -s "$TRACKED_MANIFEST" "$DESTINATION/nodus-r7-experimental.json"; then
  /usr/bin/python3 "$NODUS_ROOT/scripts/verify_development_model.py" \
    --manifest "$TRACKED_MANIFEST" \
    --model-directory "$DESTINATION"
  echo "Nodus R7 Experimental bundle is already current"
  exit 0
fi

rm -rf "$DESTINATION"
mkdir -p "$(dirname "$DESTINATION")"
/usr/bin/ditto "$CACHE_ROOT" "$DESTINATION"
/usr/bin/python3 "$NODUS_ROOT/scripts/verify_development_model.py" \
  --manifest "$TRACKED_MANIFEST" \
  --model-directory "$DESTINATION"
echo "Bundled Nodus R7 Experimental from the verified local developer cache"
