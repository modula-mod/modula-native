from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import yaml
from build_model_manifest import build_manifest
from common import ROOT, resolve_model_path, sha256


def run(command: list[str]) -> None:
    subprocess.run(command, cwd=ROOT, env={**os.environ, "HF_HOME": str(ROOT / ".cache/huggingface")}, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Fuse and quantize an evaluated Nodus adapter")
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    config = yaml.safe_load(args.config.read_text())
    adapter = (ROOT / config["adapter_path"]).resolve()
    if not adapter.exists():
        raise SystemExit(f"Adapter not found: {adapter}")
    base = resolve_model_path(config)
    model_slug = config["model"].split("/")[-1].lower()
    fused = ROOT / "artifacts" / f"nodus-v0.1-{model_slug}-fused"
    output = args.output.resolve() if args.output else ROOT / "artifacts" / f"nodus-v0.1-{model_slug}-4bit"
    run([
        sys.executable, "-m", "mlx_lm", "fuse", "--model", base,
        "--adapter-path", str(adapter), "--save-path", str(fused),
    ])
    run([
        sys.executable, "-m", "mlx_lm", "convert", "--hf-path", str(fused),
        "--mlx-path", str(output), "--quantize", "--q-bits", "4", "--q-group-size", "64",
    ])
    shutil.copyfile(ROOT / "licenses/Apache-2.0.txt", output / "LICENSE")
    catalog = json.loads((ROOT / "licenses/base-models.json").read_text())
    base_entry = next(
        item for item in catalog["models"]
        if item["model"] == config["model"] and item["revision"] == config["revision"]
    )
    manifest = build_manifest(
        output, base_model=base_entry["model"], base_revision=base_entry["revision"],
        parameters=base_entry["parameters"], license_id=base_entry["license"],
    )
    evidence = {
        "status": "passed",
        "base": config["model"],
        "baseRevision": config["revision"],
        "adapterPath": str(adapter),
        "adapterFiles": {
            str(path.relative_to(adapter)): sha256(path)
            for path in sorted(adapter.rglob("*")) if path.is_file()
        },
        "artifactPath": str(output),
        "artifactHash": manifest["artifactHash"],
        "quantization": manifest["quantization"],
    }
    report = ROOT / "reports/runs/export-evidence.json"
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")
    print(json.dumps(evidence, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
