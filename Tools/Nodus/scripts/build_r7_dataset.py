from __future__ import annotations

import argparse
import copy
import json
import random
import shutil
from collections import Counter, defaultdict
from pathlib import Path

from common import ROOT, sha256, write_jsonl


REVISION = "nodus-training-v0.2-r7-task-enhanced"
DEFAULT_QUOTAS = {
    "GENERAL_ANSWER": 2_300,
    "SUMMARIZE": 100,
    "MODULA_ANSWER": 1_200,
    "CLASSIFY_FRESHNESS": 300,
    "SHOULD_ABSTAIN": 300,
    "VERIFY_RECOMMENDATION": 240,
    "STRUCTURED_ACTION": 260,
    "CLASSIFY_INTENT": 100,
}


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def task_enhanced_sample(
    records: list[dict], quotas: dict[str, int], *, seed: int
) -> list[dict]:
    pools: dict[str, list[dict]] = defaultdict(list)
    for record in records:
        pools[record["metadata"]["taskMode"]].append(record)

    missing = sorted(set(quotas) - set(pools))
    if missing:
        raise ValueError(f"source dataset is missing task modes: {', '.join(missing)}")

    selected: list[dict] = []
    for offset, (mode, quota) in enumerate(sorted(quotas.items())):
        pool = list(pools[mode])
        random.Random(seed + offset).shuffle(pool)
        for index in range(quota):
            value = copy.deepcopy(pool[index % len(pool)])
            value["metadata"]["samplingOccurrence"] = index // len(pool)
            value["metadata"]["samplingRevision"] = REVISION
            selected.append(value)

    random.Random(seed + 100).shuffle(selected)
    return selected


def build(source_dir: Path, output_dir: Path, *, seed: int = 71) -> dict:
    source_train = source_dir / "train.jsonl"
    sampled = task_enhanced_sample(read_jsonl(source_train), DEFAULT_QUOTAS, seed=seed)
    output_dir.mkdir(parents=True, exist_ok=True)
    train_path = output_dir / "train.jsonl"
    write_jsonl(train_path, sampled)
    for split in ("valid", "test"):
        shutil.copyfile(source_dir / f"{split}.jsonl", output_dir / f"{split}.jsonl")

    counts = Counter(item["metadata"]["taskMode"] for item in sampled)
    manifest = {
        "schemaVersion": 2,
        "datasetRevision": REVISION,
        "parentRevision": "nodus-training-v0.2",
        "strategy": "deterministic-task-enhanced-resampling",
        "seed": seed,
        "trainCount": len(sampled),
        "taskModeDistribution": dict(sorted(counts.items())),
        "sourceTrainingSHA256": "sha256:" + sha256(source_train),
        "trainSHA256": "sha256:" + sha256(train_path),
        "validationSHA256": "sha256:" + sha256(output_dir / "valid.jsonl"),
        "testSHA256": "sha256:" + sha256(output_dir / "test.jsonl"),
        "note": (
            "Validation and test splits are unchanged. Exact training-example repetition is "
            "intentional sampling weight, not additional semantic diversity."
        ),
    }
    manifest_text = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    (output_dir / "training-manifest.json").write_text(manifest_text)
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        type=Path,
        default=ROOT / "data/generated/nodus-training-v0.2",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "data/generated/nodus-training-v0.2-r7",
    )
    parser.add_argument("--seed", type=int, default=71)
    args = parser.parse_args()
    print(json.dumps(build(args.source, args.output, seed=args.seed), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
