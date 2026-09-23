from __future__ import annotations

import argparse
import json
import time
from collections import defaultdict
from pathlib import Path
from typing import Any

import yaml
from mlx_lm import generate, load
from mlx_lm.sample_utils import make_sampler

from common import ROOT, normalize, read_jsonl, resolve_model_path
from task_contract import (
    TaskMode,
    classification_label,
    json_object,
    messages_for,
    normalize_generated_output,
)


CLASSIFICATION_MODES = {
    TaskMode.CLASSIFY,
    TaskMode.CLASSIFY_FRESHNESS,
    TaskMode.SHOULD_ABSTAIN,
    TaskMode.VERIFY_RECOMMENDATION,
    TaskMode.CLASSIFY_INTENT,
}


def prompt_for(tokenizer, mode: TaskMode | str, input_text: str) -> str:
    return tokenizer.apply_chat_template(
        messages_for(mode, input_text),
        tokenize=False,
        add_generation_prompt=True,
        enable_thinking=False,
    )


def _contains(text: str, term: str) -> bool:
    return normalize(term) in normalize(text)


def _subset(expected: Any, actual: Any) -> bool:
    if isinstance(expected, dict):
        return isinstance(actual, dict) and all(
            key in actual and _subset(value, actual[key]) for key, value in expected.items()
        )
    if isinstance(expected, list):
        return isinstance(actual, list) and expected == actual
    return expected == actual


def score_case(case: dict, raw_output: str) -> tuple[bool, str]:
    mode = TaskMode(case["taskMode"])
    output = normalize_generated_output(raw_output)
    forbidden = case.get("forbidden", [])
    if any(_contains(output, term) for term in forbidden):
        return False, "forbidden_claim"
    if mode in CLASSIFICATION_MODES:
        label = classification_label(output)
        return label == case["expected"], "correct" if label == case["expected"] else "wrong_label"
    if mode == TaskMode.STRUCTURED_ACTION:
        parsed = json_object(output)
        if parsed is None:
            return False, "invalid_json"
        passed = _subset(case["expectedSubset"], parsed)
        return passed, "correct" if passed else "schema_mismatch"
    groups = case.get("requiredAnyGroups", [])
    passed = all(any(_contains(output, term) for term in group) for group in groups)
    return passed, "correct" if passed else "missing_semantic_element"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--suite", action="append")
    parser.add_argument("--adapter", type=Path, help="Override the config adapter for checkpoint re-evaluation")
    parser.add_argument("--adapter-weights", type=Path, help="Load a saved checkpoint file after constructing adapter layers")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    config = yaml.safe_load(args.config.read_text())
    local_model = resolve_model_path(config)
    adapter = str(args.adapter.resolve()) if args.adapter else config.get("adapter_path")
    if adapter:
        adapter_path = Path(adapter)
        adapter = str(adapter_path if adapter_path.is_absolute() else (ROOT / adapter_path).resolve())
    model, tokenizer = load(local_model, adapter_path=adapter)
    if args.adapter_weights:
        model.load_weights(str(args.adapter_weights.resolve()), strict=False)
    suites = args.suite or [
        "general-v2", "modula-v2", "freshness-v2", "abstention-v2",
        "structured-action-v2", "hallucination-v2", "verification-v2",
    ]
    results: list[dict] = []
    for suite in suites:
        for case in read_jsonl(ROOT / f"evals/{suite}.jsonl"):
            mode = TaskMode(case["taskMode"])
            max_tokens = 24 if mode in CLASSIFICATION_MODES else (160 if mode == TaskMode.STRUCTURED_ACTION else 192)
            started = time.perf_counter()
            raw = generate(
                model,
                tokenizer,
                prompt=prompt_for(tokenizer, mode, case["input"]),
                max_tokens=max_tokens,
                sampler=make_sampler(temp=0.0),
                verbose=False,
            )
            elapsed = time.perf_counter() - started
            passed, reason = score_case(case, raw)
            normalized_output = normalize_generated_output(raw)
            results.append({
                "suite": suite,
                "id": case["id"],
                "domain": case["domain"],
                "taskMode": mode.value,
                "input": case["input"],
                "expected": case.get("expected", case.get("expectedSubset")),
                "output": normalized_output,
                "rawOutput": raw,
                "passed": passed,
                "scoreReason": reason,
                "durationSeconds": round(elapsed, 3),
            })
            print(f"{suite}/{case['id']}: {'PASS' if passed else 'FAIL'} ({elapsed:.1f}s)", flush=True)

    per_suite = {}
    per_domain = {}
    for suite in suites:
        selected = [item for item in results if item["suite"] == suite]
        per_suite[suite] = round(sum(item["passed"] for item in selected) / len(selected), 4)
    for domain in sorted({item["domain"] for item in results}):
        selected = [item for item in results if item["domain"] == domain]
        per_domain[domain] = round(sum(item["passed"] for item in selected) / len(selected), 4)

    abstention = [item for item in results if item["taskMode"] == TaskMode.SHOULD_ABSTAIN]
    non_abstention = [item for item in abstention if item["expected"] != "abstain"]
    refusal_false_positives = [
        item for item in abstention
        if item["output"] and classification_label(item["output"]) == "abstain"
        and item["expected"] != "abstain"
    ]
    structured = [item for item in results if item["taskMode"] == TaskMode.STRUCTURED_ACTION]
    unsupported = [
        item for item in structured
        if isinstance(item["expected"], dict) and item["expected"].get("type") == "unsupported"
    ]
    authority_domains = {"Authority", "GAIA", "AKI", "Governor", "Local Intelligence"}
    authority = [item for item in results if item["domain"] in authority_domains]
    report = {
        "schemaVersion": 2,
        "evaluationRevision": "nodus-eval-v2",
        "model": config["model"],
        "revision": config["revision"],
        "adapter": adapter,
        "adapterWeights": str(args.adapter_weights.resolve()) if args.adapter_weights else None,
        "scores": per_suite,
        "scoresByDomain": per_domain,
        "abstentionAccuracy": per_suite.get("abstention-v2"),
        "falseAbstentionRate": (
            round(len(refusal_false_positives) / len(non_abstention), 4)
            if non_abstention else None
        ),
        "freshnessAccuracy": per_suite.get("freshness-v2"),
        "verificationAccuracy": per_suite.get("verification-v2"),
        "structuredSchemaValidity": (
            round(sum(json_object(item["output"]) is not None for item in structured) / len(structured), 4)
            if structured else None
        ),
        "unsupportedCapabilityRejection": (
            round(sum(item["passed"] for item in unsupported) / len(unsupported), 4)
            if unsupported else None
        ),
        "authorityAccuracy": (
            round(sum(item["passed"] for item in authority) / len(authority), 4)
            if authority else None
        ),
        "results": results,
    }
    output_path = args.output or ROOT / "reports/runs/eval-v2.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key != "results"}, indent=2))


if __name__ == "__main__":
    main()
