from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path


def calibration_bucket(result: dict) -> str:
    suite = result["suite"]
    if suite == "general-v2":
        return "general factual"
    if suite in {"modula-v2", "hallucination-v2"}:
        return "Modula factual"
    if suite == "structured-action-v2":
        return "structured action"
    if suite == "freshness-v2":
        return "freshness"
    if suite == "abstention-v2":
        return "abstention"
    if suite == "verification-v2":
        return "verification"
    return suite


def calibrate(report: dict) -> dict:
    grouped: dict[str, list[dict]] = defaultdict(list)
    for result in report["results"]:
        grouped[calibration_bucket(result)].append(result)

    bucket_reports = {}
    weighted_error = 0.0
    evaluation_count = 0
    for bucket, values in sorted(grouped.items()):
        ordered = sorted(values, key=lambda item: (item["suite"], item["id"]))
        fit = ordered[::2]
        evaluation = ordered[1::2]
        if not evaluation:
            evaluation = fit
        # Beta(2, 2) smoothing avoids false precision from small task buckets.
        confidence = (sum(bool(item["passed"]) for item in fit) + 2) / (len(fit) + 4)
        accuracy = sum(bool(item["passed"]) for item in evaluation) / len(evaluation)
        error = abs(confidence - accuracy)
        weighted_error += error * len(evaluation)
        evaluation_count += len(evaluation)
        bucket_reports[bucket] = {
            "fitCount": len(fit),
            "evaluationCount": len(evaluation),
            "confidence": round(confidence, 4),
            "accuracy": round(accuracy, 4),
            "absoluteCalibrationError": round(error, 4),
        }

    return {
        "schemaVersion": 2,
        "method": "task-separated-beta-calibration",
        "model": report["model"],
        "revision": report["revision"],
        "adapter": report.get("adapter"),
        "adapterWeights": report.get("adapterWeights"),
        "calibrationError": round(weighted_error / evaluation_count, 4),
        "evaluationCount": evaluation_count,
        "buckets": bucket_reports,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = calibrate(json.loads(args.report.read_text()))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
