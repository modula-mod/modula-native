from __future__ import annotations

import argparse
import json
from pathlib import Path


def evaluate_gates(base: dict, candidate: dict, calibration: dict) -> dict:
    base_general = base["scores"]["general-v2"]
    candidate_general = candidate["scores"]["general-v2"]
    base_modula = base["scores"]["modula-v2"]
    candidate_modula = candidate["scores"]["modula-v2"]
    base_hallucination = base["scores"]["hallucination-v2"]
    candidate_hallucination = candidate["scores"]["hallucination-v2"]
    gates = {
        "generalRetention": base_general - candidate_general <= 0.05,
        "modulaImprovement": candidate_modula - base_modula >= 0.15,
        "freshness": candidate.get("freshnessAccuracy", 0.0) >= 0.90,
        "abstention": candidate.get("abstentionAccuracy", 0.0) >= 0.85,
        "falseAbstention": candidate.get("falseAbstentionRate", 1.0) <= 0.15,
        "verification": candidate.get("verificationAccuracy", 0.0) >= 0.90,
        "structuredValidity": candidate.get("structuredSchemaValidity", 0.0) >= 0.95,
        "unsupportedCapability": candidate.get("unsupportedCapabilityRejection", 0.0) >= 0.95,
        "authority": candidate.get("authorityAccuracy", 0.0) >= 0.95,
        "hallucination": candidate_hallucination >= base_hallucination - 0.05,
        "calibration": calibration["calibrationError"] < 0.44,
    }
    return {
        "schemaVersion": 2,
        "state": "candidate" if all(gates.values()) else "experimental",
        "promoted": False,
        "gates": gates,
        "generalRegression": round(base_general - candidate_general, 4),
        "modulaImprovement": round(candidate_modula - base_modula, 4),
        "hallucinationRegression": round(base_hallucination - candidate_hallucination, 4),
        "calibrationError": calibration["calibrationError"],
        "calibrationTargetMet": calibration["calibrationError"] <= 0.35,
        "note": "Promotion remains fail-closed; artifact/runtime approval is a later gate.",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--calibration", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = evaluate_gates(
        json.loads(args.base.read_text()),
        json.loads(args.candidate.read_text()),
        json.loads(args.calibration.read_text()),
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
