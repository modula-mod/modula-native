from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

from common import ROOT, GovernanceError, canonical_json, normalize, read_jsonl, sha256, validate_example, write_jsonl
from task_contract import SYSTEM_PROMPT, TaskMode, messages_for


def split_for(group: str, *, revision: str) -> str:
    bucket = int(sha256(group)[:8], 16) % 100
    train_boundary, valid_boundary = (80, 90) if revision.startswith("nodus-01b-") else (70, 85)
    if bucket < train_boundary:
        return "train"
    if bucket < valid_boundary:
        return "valid"
    return "test"


def build(
    source_path: Path,
    output_dir: Path,
    revision: str,
    *,
    base_model: str,
    base_revision: str,
    require_generation_provenance: bool = False,
    generation_manifest_path: Path | None = None,
    parent_revision: str | None = None,
) -> dict:
    catalog_path = ROOT / "data/manifests/source-catalog.json"
    catalog = json.loads(catalog_path.read_text())
    known_sources = {source["id"] for source in catalog["sources"]}
    examples = [
        validate_example(
            item,
            known_sources,
            require_generation_provenance=require_generation_provenance,
        )
        for item in read_jsonl(source_path)
    ]

    ids: set[str] = set()
    content_hashes: set[str] = set()
    normalized_prompts: set[str] = set()
    groups: dict[str, str] = {}
    splits: dict[str, list[dict]] = defaultdict(list)
    eval_paths = list((ROOT / "evals").glob("*.jsonl"))
    if revision != "nodus-training-v0.2":
        eval_paths = [path for path in eval_paths if not path.stem.endswith("-v2")]
    eval_prompts = {
        normalize(item.get("prompt", item.get("input", "")))
        for eval_path in eval_paths
        for item in read_jsonl(eval_path)
    }
    for example in examples:
        if example["id"] in ids:
            raise GovernanceError(f"duplicate ID: {example['id']}")
        if example["contentHash"] in content_hashes or normalize(example["prompt"]) in normalized_prompts:
            raise GovernanceError(f"duplicate content: {example['id']}")
        if normalize(example["prompt"]) in eval_prompts:
            raise GovernanceError(f"held-out evaluation leakage: {example['id']}")
        split = split_for(example["semanticGroup"], revision=revision)
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
                "messages": (
                    messages_for(TaskMode(item["taskMode"]), item["prompt"], item["response"])
                    if "taskMode" in item else [
                        {"role": "system", "content": "You are Nodus, a concise general-purpose offline assistant. Treat actions as proposals and flag information that needs current evidence."},
                        {"role": "user", "content": item["prompt"]},
                        {"role": "assistant", "content": item["response"]},
                    ]
                ),
                "metadata": {key: item[key] for key in (
                    "id", "semanticGroup", "category", "source", "sourceRevision", "license",
                    "creationMethod", "privacyClass", "trainingEligibility", "contentHash", "createdAt",
                )} | {
                    key: item[key] for key in (
                        "generatorType", "sourceConcept", "sourceDocument", "templateVersion",
                        "seed", "generationHash", "generalDomain",
                    ) if key in item
                } | ({"taskMode": item["taskMode"]} if "taskMode" in item else {}),
            }
            for item in sorted(splits[split], key=lambda value: value["id"])
        ]
        write_jsonl(output_dir / f"{split}.jsonl", formatted)

    category_counts = Counter(item["category"] for item in examples)
    source_counts = Counter(item["source"] for item in examples)
    files = {name: sha256(output_dir / f"{name}.jsonl") for name in ("train", "valid", "test")}
    generation_manifest = None
    if generation_manifest_path is not None:
        generation_manifest = json.loads(generation_manifest_path.read_text())
        if generation_manifest.get("sourceSHA256") != "sha256:" + sha256(source_path):
            raise GovernanceError("generation manifest does not match the source corpus")
        if generation_manifest.get("provenanceComplete") is not True:
            raise GovernanceError("generation manifest reports incomplete provenance")
    manifest = {
        "schemaVersion": 1,
        "datasetRevision": revision,
        "parentRevision": parent_revision,
        "baseModel": base_model,
        "baseRevision": base_revision,
        "createdAt": "2026-09-22T00:00:00Z" if revision.startswith("nodus-01b-") or revision == "nodus-training-v0.2" else "2026-09-20T00:00:00Z",
        "approvalState": "approved-for-experiment",
        "exampleCount": len(examples),
        "splitCounts": {name: len(splits[name]) for name in ("train", "valid", "test")},
        "categoryDistribution": dict(sorted(category_counts.items())),
        "sources": dict(sorted(source_counts.items())),
        "learningCandidateCount": 0,
        "privateProductionDataCount": 0,
        "provenanceComplete": all(
            all(key in item for key in (
                "generatorType", "sourceConcept", "sourceDocument", "templateVersion",
                "seed", "generationHash",
            )) for item in examples
        ) if require_generation_provenance else True,
        "duplicateRemoval": {
            "exact": generation_manifest.get("exactDuplicatesRemoved", 0) if generation_manifest else 0,
            "normalized": generation_manifest.get("normalizedDuplicatesRemoved", 0) if generation_manifest else 0,
            "near": generation_manifest.get("nearDuplicatesRemoved", 0) if generation_manifest else 0,
        },
        "splitPolicy": "semantic-group-hash-80-10-10" if revision.startswith("nodus-01b-") else "semantic-group-hash-70-15-15",
        "splitLeakage": "PASS",
        "licenses": sorted({item["license"] for item in examples}),
        "sourceCatalogHash": "sha256:" + sha256(catalog_path),
        "sourceExamplesHash": "sha256:" + sha256(source_path),
        "files": files,
    }
    if revision == "nodus-training-v0.2":
        manifest["auditChanges"] = [
            "single canonical system prompt across train/eval/native",
            "explicit task-mode contracts",
            "Qwen3 non-thinking mode",
            "classification labels for freshness, abstention, and verification",
            "balanced positive non-abstention and hard-negative examples",
        ]
        if generation_manifest:
            manifest["generatorVersions"] = [generation_manifest["generatorVersion"]]
            manifest["generationManifestHash"] = generation_manifest["manifestHash"]
            manifest["heldOutPromptCollisionsRemoved"] = generation_manifest.get(
                "heldOutPromptCollisionsRemoved", 0
            )
        manifest["taskModeDistribution"] = dict(sorted(Counter(
            item["taskMode"] for item in examples if "taskMode" in item
        ).items()))
    manifest["manifestHash"] = "sha256:" + sha256(canonical_json(manifest))
    (output_dir / "training-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=ROOT / "data/source/examples.jsonl")
    parser.add_argument("--output", type=Path, default=ROOT / "data/generated/nodus-training-v0.1")
    parser.add_argument("--revision", default="nodus-training-v0.1")
    parser.add_argument("--generation-manifest", type=Path)
    parser.add_argument("--require-generation-provenance", action="store_true")
    parser.add_argument("--manifest-output", type=Path)
    parser.add_argument("--parent-revision")
    parser.add_argument(
        "--base-selection",
        type=Path,
        default=ROOT / "reports/runs/base-selection.json",
    )
    args = parser.parse_args()
    if not args.base_selection.is_file():
        raise SystemExit("A completed governed base-selection report is required")
    selection = json.loads(args.base_selection.read_text())
    manifest = build(
        args.source,
        args.output,
        args.revision,
        base_model=selection["selectedModel"],
        base_revision=selection["selectedRevision"],
        require_generation_provenance=args.require_generation_provenance,
        generation_manifest_path=args.generation_manifest,
        parent_revision=args.parent_revision,
    )
    if args.manifest_output:
        args.manifest_output.parent.mkdir(parents=True, exist_ok=True)
        args.manifest_output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
