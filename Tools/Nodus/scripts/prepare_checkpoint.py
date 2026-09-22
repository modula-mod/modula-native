from __future__ import annotations

import argparse
import shutil
from pathlib import Path

import yaml

from common import ROOT


def main() -> None:
    parser = argparse.ArgumentParser(description="Materialize one immutable LoRA checkpoint for evaluation")
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--step", type=int, required=True)
    args = parser.parse_args()
    config = yaml.safe_load(args.config.read_text())
    source_dir = ROOT / config["adapter_path"]
    source = source_dir / f"{args.step:07d}_adapters.safetensors"
    if not source.is_file():
        raise SystemExit(f"checkpoint not found: {source}")
    name = f"{source_dir.name}-step-{args.step}"
    target_dir = ROOT / "artifacts/checkpoints" / name
    target_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target_dir / "adapters.safetensors")
    shutil.copyfile(source_dir / "adapter_config.json", target_dir / "adapter_config.json")
    derived = dict(config)
    derived["adapter_path"] = str(target_dir.relative_to(ROOT))
    derived["max_tokens"] = 160
    derived["temperature"] = 0.0
    output = ROOT / "reports/runs/checkpoint-configs" / f"{name}.yaml"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(yaml.safe_dump(derived, sort_keys=False))
    print(output)


if __name__ == "__main__":
    main()
