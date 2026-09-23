from __future__ import annotations

import argparse
import json
import random
from collections import Counter
from pathlib import Path

from build_corpus_01b import (
    GENERAL_ASSISTANT,
    MODULA_CATEGORIES,
    canonical_json,
    deduplicate,
    prepare_pool,
    record,
    sha256,
)
from common import ROOT, normalize, write_jsonl
from task_contract import TaskMode


GENERATOR_VERSION = "nodus-01c-corpus-v2"
CREATED_AT = "2026-09-22T00:00:00Z"
SOURCE_REVISION = "76540820b041a93c42629a963365e1e49175ca15"


def task_record(item: dict, mode: TaskMode, *, response: str | None = None, source: str | None = None) -> dict:
    value = dict(item)
    value["taskMode"] = mode.value
    value["templateVersion"] = GENERATOR_VERSION
    value["sourceRevision"] = SOURCE_REVISION
    value["createdAt"] = CREATED_AT
    if source:
        value["source"] = source
        value["license"] = "Modula-internal"
        value["privacyClass"] = "internal-non-secret"
    if response is not None:
        value["response"] = response
    value.pop("generationHash", None)
    value["generationHash"] = "sha256:" + sha256(canonical_json(value))
    return value


def authored(
    item_id: str,
    group: str,
    category: str,
    prompt: str,
    response: str,
    mode: TaskMode,
    seed: int,
    concept: str,
) -> dict:
    base = record(
        item_id=item_id,
        group=group,
        category=category,
        prompt=prompt,
        response=response,
        source="modula-nodus01b-spec",
        concept=concept,
        document="NODUS-01C task-separated training contract",
        seed=seed,
    )
    return task_record(base, mode, source="modula-nodus01b-spec")


def classification_records() -> dict[str, list[dict]]:
    frames = (
        "Classify: {text}", "Decide for this request: {text}", "Assess the input: {text}",
        "Use the task contract for: {text}", "Label this without explanation: {text}",
        "Return only the correct label for: {text}", "Apply the narrow classifier to: {text}",
        "No prose; classify this input: {text}", "Evaluate the category of: {text}",
        "Choose the contract label for: {text}",
    )
    freshness = {
        "stable": (
            "Who wrote {work}?", "What is {concept}?", "Explain why {phenomenon} happens.",
        ),
        "possibly_stale": (
            "Which versions of {product} are generally supported?", "What are recent practices for {concept}?",
            "Which {product} is usually considered a market leader?",
        ),
        "current_data_required": (
            "What is {subject} right now?", "What happened with {subject} today?", "Give the latest {subject}.",
        ),
        "unknown": (
            "What is in the unpublished {subject}?", "Describe the undocumented {subject}.",
            "State the result from the unavailable {subject}.",
        ),
    }
    values = {
        "stable": [
            {"work": "Hamlet", "concept": "gravity", "phenomenon": "Moon phases"},
            {"work": "Pride and Prejudice", "concept": "photosynthesis", "phenomenon": "seasons"},
            {"work": "The Odyssey", "concept": "DNS", "phenomenon": "tides"},
            {"work": "Macbeth", "concept": "a stack", "phenomenon": "rain"},
        ],
        "possibly_stale": [
            {"product": "iOS", "concept": "password security"}, {"product": "Swift", "concept": "browser support"},
            {"product": "local language models", "concept": "battery technology"}, {"product": "WebGPU", "concept": "API design"},
        ],
        "current_data_required": [
            {"subject": "London weather"}, {"subject": "the exchange rate"}, {"subject": "the election"},
            {"subject": "Bitcoin's price"}, {"subject": "train delays"}, {"subject": "the news"},
        ],
        "unknown": [
            {"subject": "Orinth ledger"}, {"subject": "Zorven protocol"}, {"subject": "Kestrel-9 archive"},
            {"subject": "Veloran report"}, {"subject": "redacted trial"}, {"subject": "missing minutes"},
        ],
    }
    out: dict[str, list[dict]] = {"freshness": [], "abstention": [], "verification": []}
    seed = 300_000
    for label, templates in freshness.items():
        for value_index, value in enumerate(values[label]):
            for template_index, template in enumerate(templates):
                text = template.format(**value)
                for frame_index, frame in enumerate(frames):
                    prompt = frame.format(text=text)
                    out["freshness"].append(authored(
                        f"v2-fresh-{seed}", f"v2-fresh-{label}-{value_index}-{template_index}-{frame_index}",
                        "FRESHNESS", prompt, label, TaskMode.CLASSIFY_FRESHNESS, seed, label,
                    ))
                    seed += 1

    answer_prompts = [
        "What is the capital of {place}?", "Explain {concept}.", "What does {component} do?",
    ]
    answer_values = [
        {"place": "Romania", "concept": "gravity", "component": "DNS"},
        {"place": "Japan", "concept": "photosynthesis", "component": "a cache"},
        {"place": "Canada", "concept": "binary search", "component": "Nodus"},
        {"place": "Portugal", "concept": "mitosis", "component": "the Governor"},
    ]
    uncertain_prompts = [
        "Which version of {thing} is likely still supported?", "What might {ambiguous} refer to?",
        "What is a plausible cause of {event} given incomplete evidence?",
    ]
    uncertain_values = [
        {"thing": "the API", "ambiguous": "the other record", "event": "an intermittent failure"},
        {"thing": "the library", "ambiguous": "it", "event": "a partial outage"},
        {"thing": "the model", "ambiguous": "the earlier one", "event": "a stale result"},
        {"thing": "the browser", "ambiguous": "that setting", "event": "a timeout"},
    ]
    abstain_prompts = [
        "Give the secret from {unknown}.", "State the exact result in {unknown}.",
        "Use {capability} and confirm success.",
    ]
    abstain_values = [
        {"unknown": "the unpublished ledger", "capability": "unknown.superpower"},
        {"unknown": "the private archive", "capability": "gaia.selfApprove"},
        {"unknown": "the deleted message", "capability": "shell.run"},
        {"unknown": "the unavailable trial", "capability": "governor.disable"},
    ]
    for label, templates, value_list in (
        ("answer", answer_prompts, answer_values),
        ("answer_with_uncertainty", uncertain_prompts, uncertain_values),
        ("abstain", abstain_prompts, abstain_values),
    ):
        for value_index, value in enumerate(value_list):
            for template_index, template in enumerate(templates):
                text = template.format(**value)
                for frame_index, frame in enumerate(frames):
                    out["abstention"].append(authored(
                        f"v2-abstain-{seed}", f"v2-abstain-{label}-{value_index}-{template_index}-{frame_index}",
                        "ABSTENTION", frame.format(text=text), label, TaskMode.SHOULD_ABSTAIN, seed, label,
                    ))
                    seed += 1

    verification_mapping = {
        "not_needed": ["Who wrote Hamlet?", "Explain gravity.", "What is a stack?", "What is GAIA in Modula?", "What is the capital of Canada?", "Why does the Moon have phases?"],
        "recommended": ["Which software version is probably supported?", "This source may be old; should I rely on it?", "The evidence conflicts; what should I do?", "Is this approximate attribution safe to repeat?", "Is this version-specific answer likely stale?", "Should I double-check this ambiguous claim?"],
        "required": ["What is the weather now?", "What are today's newly reported medicine side effects?", "What is the live election count?", "Is my flight delayed right now?", "What is the current legal deadline?", "Which evacuation order is active now?"],
    }
    for label, prompts in verification_mapping.items():
        for prompt_index, text in enumerate(prompts):
            for frame_index, frame in enumerate(frames):
                out["verification"].append(authored(
                    f"v2-verify-{seed}", f"v2-verify-{label}-{prompt_index}-{frame_index}",
                    "VERIFICATION_DECISION", frame.format(text=text), label,
                    TaskMode.VERIFY_RECOMMENDATION, seed, label,
                ))
                seed += 1
    return out


def build(output_dir: Path, seed: int = 41) -> dict:
    pool, removed = prepare_pool()
    selected: list[dict] = []
    held_out_prompts = {
        normalize(item.get("prompt", item.get("input", "")))
        for path in (ROOT / "evals").glob("*.jsonl")
        for line in path.read_text().splitlines()
        if line.strip()
        for item in [json.loads(line)]
    }
    held_out_collisions = 0

    def held_out_filtered(items: list[dict]) -> list[dict]:
        nonlocal held_out_collisions
        output = []
        for item in items:
            if normalize(item["prompt"]) in held_out_prompts:
                held_out_collisions += 1
            else:
                output.append(item)
        return output

    general = held_out_filtered(list(pool[GENERAL_ASSISTANT]))
    random.Random(seed).shuffle(general)
    for item in general[:3_600]:
        mode = TaskMode.SUMMARIZE if item["prompt"].lower().startswith("summarize") else TaskMode.GENERAL_ANSWER
        selected.append(task_record(item, mode))

    per_category = {category: 134 for category in MODULA_CATEGORIES}
    per_category[MODULA_CATEGORIES[-1]] -= sum(per_category.values()) - 1_200
    for offset, category in enumerate(MODULA_CATEGORIES):
        candidates = held_out_filtered(list(pool[category]))
        random.Random(seed + offset + 1).shuffle(candidates)
        selected.extend(task_record(item, TaskMode.MODULA_ANSWER) for item in candidates[:per_category[category]])

    classes = classification_records()
    random.Random(seed + 20).shuffle(classes["freshness"])
    random.Random(seed + 21).shuffle(classes["abstention"])
    random.Random(seed + 22).shuffle(classes["verification"])
    selected.extend(classes["freshness"][:240])
    selected.extend(classes["abstention"][:240])
    selected.extend(classes["verification"][:180])

    structured = held_out_filtered(list(pool["STRUCTURED_INTENT"]))
    random.Random(seed + 23).shuffle(structured)
    selected.extend(task_record(item, TaskMode.STRUCTURED_ACTION) for item in structured[:300])

    authority = held_out_filtered(list(pool["AUTHORITY_BOUNDARIES"]))
    random.Random(seed + 24).shuffle(authority)
    selected.extend(task_record(item, TaskMode.MODULA_ANSWER) for item in authority[:120])

    unknown = held_out_filtered(list(pool["UNKNOWN_CAPABILITY"]))
    random.Random(seed + 25).shuffle(unknown)
    selected.extend(task_record(item, TaskMode.CLASSIFY_INTENT, response="unsupported") for item in unknown[:120])

    selected, final_removed = deduplicate(selected)
    if len(selected) < 6_000:
        existing_prompts = {normalize(item["prompt"]) for item in selected}
        for item in general[3_600:]:
            if normalize(item["prompt"]) in existing_prompts:
                continue
            mode = TaskMode.SUMMARIZE if item["prompt"].lower().startswith("summarize") else TaskMode.GENERAL_ANSWER
            selected.append(task_record(item, mode))
            existing_prompts.add(normalize(item["prompt"]))
            if len(selected) == 6_000:
                break
    if len(selected) != 6_000:
        raise ValueError(f"expected 6000 unique examples, got {len(selected)}")
    selected.sort(key=lambda item: item["id"])
    output_dir.mkdir(parents=True, exist_ok=True)
    source_path = output_dir / "nodus-training-v0.2-source.jsonl"
    write_jsonl(source_path, selected)
    category_counts = Counter(item["category"] for item in selected)
    mode_counts = Counter(item["taskMode"] for item in selected)
    manifest = {
        "schemaVersion": 2,
        "generatorVersion": GENERATOR_VERSION,
        "datasetRevision": "nodus-training-v0.2",
        "parentRevisions": ["nodus-01b-r3-v1", "nodus-01b-r4-v1", "nodus-01b-r5-v1"],
        "seed": seed,
        "createdAt": CREATED_AT,
        "sourceRevision": SOURCE_REVISION,
        "exampleCount": len(selected),
        "categoryDistribution": dict(sorted(category_counts.items())),
        "taskModeDistribution": dict(sorted(mode_counts.items())),
        "exactDuplicatesRemoved": removed["exact"] + final_removed["exact"],
        "normalizedDuplicatesRemoved": removed["normalized"] + final_removed["normalized"],
        "nearDuplicatesRemoved": removed["near"] + final_removed["near"],
        "heldOutPromptCollisionsRemoved": held_out_collisions,
        "privateProductionDataCount": 0,
        "provenanceComplete": True,
        "sourceFile": source_path.name,
        "sourceSHA256": "sha256:" + sha256(source_path),
    }
    manifest["manifestHash"] = "sha256:" + sha256(canonical_json(manifest))
    manifest_path = output_dir / "nodus-training-v0.2-generation-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "data/generated/nodus-01c-source")
    args = parser.parse_args()
    print(json.dumps(build(args.output), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
