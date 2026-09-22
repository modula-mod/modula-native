from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path


def fit(report: dict) -> dict:
    buckets: dict[str, list[bool]] = defaultdict(list)
    for result in report["results"]:
        buckets[result["confidenceBucket"]].append(bool(result["passed"]))
    # Beta(2, 2) smoothing prevents tiny validation buckets from yielding 0 or 1.
    calibrated = {
        name: round((sum(values) + 2) / (len(values) + 4), 4)
        for name, values in sorted(buckets.items())
    }
    total = sum(len(values) for values in buckets.values())
    correct = sum(sum(values) for values in buckets.values())
    fallback = round((correct + 2) / (total + 4), 4)
    return {
        "schemaVersion": 1,
        "method": "deterministic-bucket-beta-calibration",
        "fitScope": "held-out-calibration-validation",
        "sourceModel": report["model"],
        "sourceRevision": report["revision"],
        "sourceAdapter": report.get("adapter"),
        "caseCount": total,
        "buckets": calibrated,
        "fallback": fallback,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    calibration = fit(json.loads(args.report.read_text()))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(calibration, indent=2, sort_keys=True) + "\n")
    print(json.dumps(calibration, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
