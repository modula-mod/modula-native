#!/bin/sh
set -eu
MODULA_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
. "$MODULA_ROOT/ios/.xcode.env"
[ "$("$NODE_BINARY" -p 'process.versions.node.split(".")[0]')" = 22 ] || { echo 'error: Modula runtime requires Node 22'; exit 1; }
export PROJECT_ROOT="$MODULA_ROOT/runtime"
export REACT_NATIVE_PATH="$MODULA_ROOT/node_modules/react-native"
export ENTRY_FILE=index.js
export FORCE_BUNDLING=1
export NODE_BINARY
/bin/sh "$REACT_NATIVE_PATH/scripts/react-native-xcode.sh"
