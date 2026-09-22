from __future__ import annotations

import argparse
import json
import time
from collections import defaultdict
from pathlib import Path

import yaml
from mlx_lm import generate, load
from mlx_lm.sample_utils import make_sampler

from common import ROOT, normalize, read_jsonl, resolve_model_path


SYSTEM = "You are Nodus, a concise general-purpose offline assistant. Do not invent live information. State when current evidence is required. Nodus proposes actions; Modula validates and authorizes them."


def prompt_for(tokenizer, prompt: str) -> str:
    messages = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": prompt}]
    try:
        return tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True, enable_thinking=False)
    except TypeError:
        return tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)


def freshness_for(prompt: str) -> str:
    text = normalize(prompt)
    live = ("today", "current", "right now", "latest", "newest", "yesterday", "weather", "news")
    if any(marker in text for marker in live):
        return "current_data_required"
    possibly_stale = ("recent", "modern", "supported version", "available model", "market leader")
    if any(marker in text for marker in possibly_stale):
        return "possibly_stale"
    unknown = ("undocumented", "unpublished", "unknown protocol", "unidentified", "unspecified source")
    if any(marker in text for marker in unknown):
        return "unknown"
    return "stable"


def confidence_bucket(output: str, predicted_freshness: str) -> str:
    text = normalize(output)
    if predicted_freshness == "current_data_required":
        return "current_data"
    if is_abstention(output):
        return "abstention"
    if predicted_freshness in {"possibly_stale", "unknown"} or any(
        marker in text for marker in ("uncertain", "not enough", "may be stale", "cannot verify")
    ):
        return "uncertain"
    if len(text.split()) < 5:
        return "stable_short"
    return "stable_answer"


def confidence_for(
    output: str,
    predicted_freshness: str,
    calibration: dict | None = None,
) -> float:
    """Estimate confidence from model/runtime signals without consulting ground truth."""
    text = normalize(output)
    score = 0.62
    if predicted_freshness == "current_data_required":
        score = 0.32 if any(word in text for word in ("current", "verify", "live", "cannot")) else 0.16
    elif predicted_freshness == "possibly_stale":
        score = 0.48
    elif predicted_freshness == "unknown":
        score = 0.36
    if len(text.split()) < 4:
        score -= 0.12
    if any(word in text for word in ("uncertain", "not enough", "verify", "may be stale")):
        score -= 0.08
    uncalibrated = round(max(0.02, min(0.98, score)), 3)
    if calibration is None:
        return uncalibrated
    bucket = confidence_bucket(output, predicted_freshness)
    calibrated = calibration.get("buckets", {}).get(bucket)
    if calibrated is None:
        calibrated = calibration.get("fallback", uncalibrated)
    return round(max(0.02, min(0.98, float(calibrated))), 3)


def is_abstention(output: str) -> bool:
    text = normalize(output)
    return any(marker in text for marker in (
        "not enough reliable", "do not have enough", "don t have enough",
        "cannot answer reliably", "unable to verify", "no reliable information",
        "cannot provide", "can t provide", "not publicly available", "not documented",
        "undocumented", "no access to", "don t have access to", "do not have access to",
    ))


def score_case(case: dict, output: str) -> bool:
    text = normalize(output)
    if "exact" in case:
        return text == normalize(case["exact"])
    forbidden = any(normalize(term) in text for term in case.get("forbidden", []))
    if case.get("abstentionExpected"):
        return is_abstention(output) and not forbidden
    if case.get("currentDataExpected"):
        recognizes_live_dependency = any(marker in text for marker in (
            "current", "real time", "latest", "up to date", "today", "live data",
        ))
        recommends_check = any(marker in text for marker in (
            "verify", "check", "reliable source", "trusted source", "weather service",
        ))
        return recognizes_live_dependency and recommends_check and not forbidden
    required = all(normalize(term) in text for term in case.get("required", []))
    any_required = case.get("anyRequired", [])
    if any_required:
        required = required and any(normalize(term) in text for term in any_required)
    return required and not any(
        normalize(term) in text for term in case.get("forbidden", [])
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--suite", action="append")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--calibration", type=Path)
    args = parser.parse_args()
    config = yaml.safe_load(args.config.read_text())
    calibration = json.loads(args.calibration.read_text()) if args.calibration else None
    local_model = resolve_model_path(config)
    adapter = config.get("adapter_path")
    if adapter:
        adapter = str((ROOT / adapter).resolve())
    model, tokenizer = load(local_model, adapter_path=adapter)
    suites = args.suite or ["general", "modula", "freshness", "uncertainty"]
    results = []
    for suite in suites:
        for case in read_jsonl(ROOT / f"evals/{suite}.jsonl"):
            started = time.perf_counter()
            output = generate(
                model,
                tokenizer,
                prompt=prompt_for(tokenizer, case["prompt"]),
                max_tokens=int(config.get("max_tokens", 160)),
                sampler=make_sampler(temp=float(config.get("temperature", 0.0))),
                verbose=False,
            )
            elapsed = time.perf_counter() - started
            passed = score_case(case, output)
            predicted_freshness = freshness_for(case["prompt"])
            uncalibrated_confidence = confidence_for(output, predicted_freshness)
            confidence = confidence_for(output, predicted_freshness, calibration)
            abstained = is_abstention(output)
            results.append({
                "suite": suite, "id": case["id"], "domain": case["domain"], "prompt": case["prompt"],
                "output": output, "passed": passed, "confidence": confidence,
                "uncalibratedConfidence": uncalibrated_confidence,
                "confidenceBucket": confidence_bucket(output, predicted_freshness),
                "expectedFreshness": case["freshness"], "predictedFreshness": predicted_freshness,
                "freshnessPassed": predicted_freshness == case["freshness"], "durationSeconds": round(elapsed, 3),
                "abstentionExpected": bool(case.get("abstentionExpected", False)), "abstained": abstained,
                "currentDataExpected": bool(case.get("currentDataExpected", False)),
            })
            print(f"{suite}/{case['id']}: {'PASS' if passed else 'FAIL'} ({elapsed:.1f}s)", flush=True)

    per_suite = {}
    for suite in suites:
        selected = [item for item in results if item["suite"] == suite]
        per_suite[suite] = round(sum(item["passed"] for item in selected) / len(selected), 4)
    per_domain = {}
    for domain in sorted({item["domain"] for item in results}):
        selected = [item for item in results if item["domain"] == domain]
        per_domain[domain] = round(sum(item["passed"] for item in selected) / len(selected), 4)
    per_suite_domain = {}
    for suite in suites:
        suite_results = [item for item in results if item["suite"] == suite]
        per_suite_domain[suite] = {}
        for domain in sorted({item["domain"] for item in suite_results}):
            selected = [item for item in suite_results if item["domain"] == domain]
            per_suite_domain[suite][domain] = round(
                sum(item["passed"] for item in selected) / len(selected), 4
            )
    general_per_domain = {}
    for domain in sorted({item["domain"] for item in results if item["suite"] == "general"}):
        selected = [
            item for item in results
            if item["suite"] == "general" and item["domain"] == domain
        ]
        general_per_domain[domain] = round(
            sum(item["passed"] for item in selected) / len(selected), 4
        )
    # Live-data and deliberate-abstention prompts evaluate safe behavior, not possession
    # of the requested fact. Calibrating knowledge confidence against those behavioral
    # passes would incorrectly penalize the low confidence that the product requires.
    calibration_cases = [
        item for item in results
        if item["expectedFreshness"] == "stable" and not item["abstentionExpected"]
    ]
    calibration_error = round(
        sum(abs(item["confidence"] - float(item["passed"])) for item in calibration_cases)
        / len(calibration_cases), 4
    )
    uncalibrated_calibration_error = round(
        sum(abs(item["uncalibratedConfidence"] - float(item["passed"])) for item in calibration_cases)
        / len(calibration_cases), 4
    )
    overconfidence = round(
        sum(item["confidence"] >= 0.7 and not item["passed"] for item in calibration_cases)
        / len(calibration_cases), 4
    )
    underconfidence = round(
        sum(item["confidence"] < 0.5 and item["passed"] for item in calibration_cases)
        / len(calibration_cases), 4
    )
    reliability_buckets = []
    for lower, upper in ((0.0, 0.25), (0.25, 0.5), (0.5, 0.75), (0.75, 1.01)):
        selected = [item for item in calibration_cases if lower <= item["confidence"] < upper]
        reliability_buckets.append({
            "range": [lower, min(1.0, upper)],
            "count": len(selected),
            "meanConfidence": round(sum(item["confidence"] for item in selected) / len(selected), 4) if selected else None,
            "accuracy": round(sum(item["passed"] for item in selected) / len(selected), 4) if selected else None,
        })
    abstention_cases = [item for item in results if item["abstentionExpected"]]
    non_abstention_cases = [
        item for item in results
        if not item["abstentionExpected"] and not item["currentDataExpected"]
    ]
    report = {
        "schemaVersion": 1, "model": config["model"], "revision": config["revision"], "adapter": adapter,
        "scores": per_suite, "scoresByDomain": per_domain,
        "scoresBySuiteDomain": per_suite_domain,
        "generalScoresByDomain": general_per_domain,
        "freshnessAccuracy": round(sum(item["freshnessPassed"] for item in results) / len(results), 4),
        "calibrationError": calibration_error,
        "uncalibratedCalibrationError": uncalibrated_calibration_error,
        "calibrationMethod": calibration.get("method") if calibration else "legacy-deterministic-signals",
        "calibrationArtifact": str(args.calibration.resolve()) if args.calibration else None,
        "calibrationScope": "stable_non_abstention",
        "calibrationCaseCount": len(calibration_cases),
        "overconfidenceRate": overconfidence,
        "underconfidenceRate": underconfidence,
        "abstentionAccuracy": round(
            sum(item["abstained"] for item in abstention_cases) / len(abstention_cases), 4
        ) if abstention_cases else None,
        "falseAbstentionRate": round(
            sum(item["abstained"] for item in non_abstention_cases) / len(non_abstention_cases), 4
        ) if non_abstention_cases else None,
        "reliabilityBuckets": reliability_buckets,
        "results": results,
    }
    output_path = args.output or ROOT / "reports/runs" / f"eval-{config['model'].split('/')[-1]}{'-nodus' if adapter else '-base'}.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key != "results"}, indent=2))


if __name__ == "__main__":
    main()
