from __future__ import annotations

import argparse
import json
from pathlib import Path

from common import ROOT


def choose_base(reports: list[dict], catalog: dict) -> dict:
    reviewed = {
        (item["model"], item["revision"]): item
        for item in catalog["models"]
        if item.get("reviewStatus") == "reviewed"
    }
    ranking = []
    seen: set[tuple[str, str]] = set()
    for report in reports:
        if report.get("adapter") is not None:
            raise ValueError("base selection accepts only unadapted benchmark reports")
        key = (report["model"], report["revision"])
        if key in seen:
            raise ValueError(f"duplicate base benchmark: {key[0]}@{key[1]}")
        seen.add(key)
        if key not in reviewed:
            raise ValueError(f"unreviewed model or revision: {key[0]}@{key[1]}")
        license_entry = reviewed[key]
        scores = report["scores"]
        ranking.append({
            "model": report["model"],
            "revision": report["revision"],
            "parameters": license_entry["parameters"],
            "license": license_entry["license"],
            "general": scores["general"],
            "freshness": scores["freshness"],
            "uncertainty": scores["uncertainty"],
            "modula": scores["modula"],
            "calibrationError": report["calibrationError"],
        })

    # General capability is the primary product requirement. The remaining held-out
    # behaviors break ties in order, then lower calibration error and parameter count.
    ranking.sort(key=lambda item: (
        item["general"], item["freshness"], item["uncertainty"], item["modula"],
        -item["calibrationError"], -item["parameters"],
    ), reverse=True)
    if len(ranking) < 2:
        raise ValueError("at least two reviewed base benchmarks are required")
    winner = ranking[0]
    return {
        "schemaVersion": 1,
        "selectionPolicy": [
            "general", "freshness", "uncertainty", "modula",
            "lower_calibration_error", "lower_parameter_count",
        ],
        "selectedModel": winner["model"],
        "selectedRevision": winner["revision"],
        "ranking": ranking,
        "reason": "Selected by the predeclared lexicographic held-out policy after both reviewed bases completed identical evaluations.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Select a reviewed Nodus base only after equal benchmarks")
    parser.add_argument("reports", nargs="+", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "reports/runs/base-selection.json")
    args = parser.parse_args()
    reports = [json.loads(path.read_text()) for path in args.reports]
    catalog = json.loads((ROOT / "licenses/base-models.json").read_text())
    result = choose_base(reports, catalog)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
