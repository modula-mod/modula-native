from __future__ import annotations

import argparse
import json
from pathlib import Path

import yaml

from common import ROOT, canonical_json, sha256


def build_manifest(
    artifact: Path,
    *,
    base_model: str,
    base_revision: str,
    parameters: int,
    license_id: str,
    version: str = "Nodus v0.1",
    quantization: str = "4-bit",
    training_date: str = "2026-09-21",
) -> dict:
    artifact = artifact.resolve()
    files = sorted(path for path in artifact.rglob("*") if path.is_file() and path.name != "nodus-manifest.json")
    file_hashes = {str(path.relative_to(artifact)): sha256(path) for path in files}
    manifest = {
        "schemaVersion": 1, "nodusVersion": version, "parameters": parameters,
        "baseModel": base_model, "baseRevision": base_revision,
        "license": license_id, "fineTuningMethod": "LoRA", "datasetRevision": "nodus-training-v0.1",
        "evalSuiteRevision": "nodus-evals-v0.1", "quantization": quantization,
        "trainingDate": training_date, "knowledgeProvenance": ["modula-nodus01-spec", "modula-architecture-docs", "nodus-authored-general-replay"],
        "files": file_hashes,
    }
    # Bind provenance and runtime metadata as well as file contents. The external
    # expected hash supplied during installation pins this complete manifest.
    manifest["artifactHash"] = "sha256:" + sha256(canonical_json(manifest))
    (artifact / "nodus-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--version", default="Nodus v0.1")
    parser.add_argument("--quantization", default="4-bit")
    parser.add_argument("--training-date", default="2026-09-21")
    args = parser.parse_args()
    config = yaml.safe_load(args.config.read_text())
    catalog = json.loads((ROOT / "licenses/base-models.json").read_text())
    base = next(
        item for item in catalog["models"]
        if item["model"] == config["model"] and item["revision"] == config["revision"]
    )
    manifest = build_manifest(
        args.artifact, base_model=base["model"], base_revision=base["revision"],
        parameters=base["parameters"], license_id=base["license"],
        version=args.version, quantization=args.quantization, training_date=args.training_date,
    )
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
