from __future__ import annotations

import argparse
import json
from pathlib import Path


def checkpoint_score(report: dict, validation_loss: float) -> float:
    scores = report["scores"]
    quality = (
        0.25 * scores.get("general-v2", 0.0)
        + 0.25 * scores.get("modula-v2", 0.0)
        + 0.15 * scores.get("freshness-v2", 0.0)
        + 0.15 * scores.get("abstention-v2", 0.0)
        + 0.10 * scores.get("verification-v2", 0.0)
        + 0.10 * scores.get("structured-action-v2", 0.0)
    )
    refusal_penalty = 0.10 * report.get("falseAbstentionRate", 0.0)
    loss_penalty = min(validation_loss, 10.0) * 0.002
    return quality - refusal_penalty - loss_penalty


def select(candidates: list[dict]) -> dict:
    if not candidates:
        raise ValueError("at least one checkpoint candidate is required")
    evaluated = []
    for candidate in candidates:
        report = candidate["report"]
        evaluated.append({
            "step": candidate["step"],
            "validationLoss": candidate["validationLoss"],
            "multiMetricScore": round(
                checkpoint_score(report, candidate["validationLoss"]), 6
            ),
            "scores": report["scores"],
            "falseAbstentionRate": report.get("falseAbstentionRate"),
        })
    selected = max(evaluated, key=lambda item: (item["multiMetricScore"], -item["step"]))
    return {
        "schemaVersion": 2,
        "method": "validation-loss-plus-task-metrics-v2",
        "selectedStep": selected["step"],
        "selectedScore": selected["multiMetricScore"],
        "candidates": sorted(evaluated, key=lambda item: item["step"]),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--candidate",
        action="append",
        required=True,
        help="STEP:VALIDATION_LOSS:REPORT_JSON",
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    candidates = []
    for raw in args.candidate:
        step, validation_loss, report_path = raw.split(":", 2)
        candidates.append({
            "step": int(step),
            "validationLoss": float(validation_loss),
            "report": json.loads(Path(report_path).read_text()),
        })
    result = select(candidates)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
