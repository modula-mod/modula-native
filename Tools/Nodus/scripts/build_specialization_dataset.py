from __future__ import annotations

import argparse
import json
from pathlib import Path

from common import ROOT, canonical_json, read_jsonl, sha256, write_jsonl


def build(parent_dir: Path, output_dir: Path, revision: str) -> dict:
    parent_manifest_path = parent_dir / "training-manifest.json"
    parent = json.loads(parent_manifest_path.read_text())
    output_dir.mkdir(parents=True, exist_ok=True)
    counts: dict[str, int] = {}
    files: dict[str, str] = {}
    for split in ("train", "valid", "test"):
        selected = [
            item for item in read_jsonl(parent_dir / f"{split}.jsonl")
            if item["metadata"]["category"] == "modula"
        ]
        if not selected:
            raise ValueError(f"specialization split is empty: {split}")
        write_jsonl(output_dir / f"{split}.jsonl", selected)
        counts[split] = len(selected)
        files[split] = sha256(output_dir / f"{split}.jsonl")
    manifest = {
        "schemaVersion": 1,
        "datasetRevision": revision,
        "parentRevision": parent["datasetRevision"],
        "parentManifestHash": parent["manifestHash"],
        "purpose": "bounded-modula-specialization-continuation",
        "baseModel": parent["baseModel"],
        "baseRevision": parent["baseRevision"],
        "createdAt": "2026-09-21T00:00:00Z",
        "approvalState": "approved-for-experiment",
        "exampleCount": sum(counts.values()),
        "splitCounts": counts,
        "categoryDistribution": {"modula": sum(counts.values())},
        "privateProductionDataCount": 0,
        "licenses": parent["licenses"],
        "files": files,
    }
    manifest["manifestHash"] = "sha256:" + sha256(canonical_json(manifest))
    (output_dir / "training-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--parent", type=Path,
        default=ROOT / "data/generated/nodus-training-v0.1",
    )
    parser.add_argument(
        "--output", type=Path,
        default=ROOT / "data/generated/nodus-specialization-v0.1",
    )
    parser.add_argument("--revision", default="nodus-specialization-v0.1")
    args = parser.parse_args()
    print(json.dumps(build(args.parent, args.output, args.revision), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
