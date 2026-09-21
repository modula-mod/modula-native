#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PYTHON_BIN=${PYTHON_BIN:-python3}

"$PYTHON_BIN" -c 'import sys; assert (3, 11) <= sys.version_info[:2] < (3, 15), sys.version'
if [ ! -x "$ROOT/.venv/bin/python" ]; then
  "$PYTHON_BIN" -m venv "$ROOT/.venv"
fi
"$ROOT/.venv/bin/python" -m pip install --upgrade 'pip==26.0.1'
"$ROOT/.venv/bin/python" -m pip install -e "$ROOT"
"$ROOT/.venv/bin/python" -m pip freeze > "$ROOT/reports/python-lock.txt"
printf 'Nodus environment ready: %s\n' "$ROOT/.venv/bin/python"
