from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

from common import ROOT, GovernanceError, canonical_json, normalize, read_jsonl, sha256, validate_example, write_jsonl


def split_for(group: str) -> str:
    bucket = int(sha256(group)[:8], 16) % 100
    if bucket < 70:
        return "train"
    if bucket < 85:
        return "valid"
    return "test"


def build(
    source_path: Path,
    output_dir: Path,
    revision: str,
    *,
    base_model: str,
    base_revision: str,
) -> dict:
    catalog_path = ROOT / "data/manifests/source-catalog.json"
    catalog = json.loads(catalog_path.read_text())
    known_sources = {source["id"] for source in catalog["sources"]}
    examples = [validate_example(item, known_sources) for item in read_jsonl(source_path)]

    ids: set[str] = set()
    content_hashes: set[str] = set()
    normalized_prompts: set[str] = set()
    groups: dict[str, str] = {}
    splits: dict[str, list[dict]] = defaultdict(list)
    eval_prompts = {
        normalize(item["prompt"])
        for eval_path in (ROOT / "evals").glob("*.jsonl")
        for item in read_jsonl(eval_path)
    }
    for example in examples:
        if example["id"] in ids:
            raise GovernanceError(f"duplicate ID: {example['id']}")
        if example["contentHash"] in content_hashes or normalize(example["prompt"]) in normalized_prompts:
            raise GovernanceError(f"duplicate content: {example['id']}")
        if normalize(example["prompt"]) in eval_prompts:
            raise GovernanceError(f"held-out evaluation leakage: {example['id']}")
        split = split_for(example["semanticGroup"])
        if example["semanticGroup"] in groups and groups[example["semanticGroup"]] != split:
            raise GovernanceError(f"semantic group crossed splits: {example['semanticGroup']}")
        groups[example["semanticGroup"]] = split
        ids.add(example["id"])
        content_hashes.add(example["contentHash"])
        normalized_prompts.add(normalize(example["prompt"]))
        splits[split].append(example)

    # Small corpora can hash into an empty split. Move whole semantic groups deterministically.
    for desired, donor in (("valid", "train"), ("test", "train")):
        if not splits[desired]:
            movable_group = sorted({item["semanticGroup"] for item in splits[donor]})[-1]
            moving = [item for item in splits[donor] if item["semanticGroup"] == movable_group]
            splits[donor] = [item for item in splits[donor] if item["semanticGroup"] != movable_group]
            splits[desired].extend(moving)
            groups[movable_group] = desired

    output_dir.mkdir(parents=True, exist_ok=True)
    for split in ("train", "valid", "test"):
        formatted = [
            {
                "messages": [
                    {"role": "system", "content": "You are Nodus, a concise general-purpose offline assistant. Treat actions as proposals and flag information that needs current evidence."},
                    {"role": "user", "content": item["prompt"]},
                    {"role": "assistant", "content": item["response"]},
                ],
                "metadata": {key: item[key] for key in (
                    "id", "semanticGroup", "category", "source", "sourceRevision", "license",
                    "creationMethod", "privacyClass", "trainingEligibility", "contentHash", "createdAt",
                )},
            }
            for item in sorted(splits[split], key=lambda value: value["id"])
        ]
        write_jsonl(output_dir / f"{split}.jsonl", formatted)

    category_counts = Counter(item["category"] for item in examples)
    source_counts = Counter(item["source"] for item in examples)
    files = {name: sha256(output_dir / f"{name}.jsonl") for name in ("train", "valid", "test")}
    manifest = {
        "schemaVersion": 1,
        "datasetRevision": revision,
        "parentRevision": None,
        "baseModel": base_model,
        "baseRevision": base_revision,
        "createdAt": "2026-09-20T00:00:00Z",
        "approvalState": "approved-for-experiment",
        "exampleCount": len(examples),
        "splitCounts": {name: len(splits[name]) for name in ("train", "valid", "test")},
        "categoryDistribution": dict(sorted(category_counts.items())),
        "sources": dict(sorted(source_counts.items())),
        "learningCandidateCount": 0,
        "privateProductionDataCount": 0,
        "licenses": sorted({item["license"] for item in examples}),
        "sourceCatalogHash": "sha256:" + sha256(catalog_path),
        "sourceExamplesHash": "sha256:" + sha256(source_path),
        "files": files,
    }
    manifest["manifestHash"] = "sha256:" + sha256(canonical_json(manifest))
    (output_dir / "training-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=ROOT / "data/source/examples.jsonl")
    parser.add_argument("--output", type=Path, default=ROOT / "data/generated/nodus-training-v0.1")
    parser.add_argument("--revision", default="nodus-training-v0.1")
    parser.add_argument(
        "--base-selection",
        type=Path,
        default=ROOT / "reports/runs/base-selection.json",
    )
    args = parser.parse_args()
    if not args.base_selection.is_file():
        raise SystemExit("A completed governed base-selection report is required")
    selection = json.loads(args.base_selection.read_text())
    print(json.dumps(build(
        args.source,
        args.output,
        args.revision,
        base_model=selection["selectedModel"],
        base_revision=selection["selectedRevision"],
    ), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
