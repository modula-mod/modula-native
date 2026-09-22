from __future__ import annotations

import argparse
import json
from pathlib import Path

from common import ROOT, read_jsonl, sha256


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--revision", required=True)
    parser.add_argument("--file", action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    files = [ROOT / "evals" / name for name in args.file]
    manifest = {
        "schemaVersion": 1,
        "revision": args.revision,
        "frozenAt": "2026-09-22T00:00:00Z",
        "heldOutFromTraining": True,
        "caseCounts": {path.stem: len(read_jsonl(path)) for path in files},
        "files": {path.name: "sha256:" + sha256(path) for path in files},
        "evaluator": {
            "path": "scripts/evaluate.py",
            "sha256": sha256(ROOT / "scripts/evaluate.py"),
            "calibrationScope": "stable_non_abstention",
            "calibrationMethod": "deterministic bucket mapping fit on calibration-valid and scored on held-out calibration-test",
            "freshnessRequires": "live-data recognition plus a recommendation to check current evidence",
            "abstentionRequires": "an explicit inability to provide undocumented or unavailable facts",
        },
    }
    args.output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
