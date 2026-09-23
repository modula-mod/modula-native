from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml
from mlx_lm import generate, load
from mlx_lm.sample_utils import make_sampler
from common import ROOT, resolve_model_path, sha256
from task_contract import TaskMode, messages_for, normalize_generated_output


def validate_config(config: dict) -> None:
    required = {
        "model", "revision", "local_model_path", "train", "fine_tune_type", "data",
        "seed", "num_layers", "batch_size", "iters", "learning_rate", "adapter_path",
        "max_seq_length", "lora_parameters",
    }
    missing = sorted(required - config.keys())
    if missing:
        raise ValueError(f"training config missing: {', '.join(missing)}")
    if config["train"] is not True or config["fine_tune_type"] != "lora":
        raise ValueError("NODUS-01 requires an enabled LoRA experiment")
    if int(config["iters"]) <= 0 or int(config["num_layers"]) <= 0:
        raise ValueError("iterations and LoRA layer count must be positive")
    if int(config["batch_size"]) <= 0 or int(config["max_seq_length"]) <= 0:
        raise ValueError("batch and sequence length must be positive")
    learning_rate = float(config["learning_rate"])
    if not 0.0 < learning_rate < 0.1:
        raise ValueError("learning rate is outside the guarded experimental range")
    lora = config["lora_parameters"]
    if int(lora.get("rank", 0)) <= 0 or not lora.get("keys"):
        raise ValueError("LoRA rank and target keys are required")


def reload_smoke(model_path: str, adapter_path: Path) -> str:
    model, tokenizer = load(model_path, adapter_path=str(adapter_path))
    messages = messages_for(TaskMode.GENERAL_ANSWER, "What is Nodus?")
    try:
        prompt = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True, enable_thinking=False
        )
    except TypeError:
        prompt = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    output = generate(
        model, tokenizer, prompt=prompt, max_tokens=48,
        sampler=make_sampler(temp=0.0), verbose=False,
    )
    output = normalize_generated_output(output)
    if not output:
        raise RuntimeError("Adapter reload generation returned no text")
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--pilot", action="store_true")
    args = parser.parse_args()
    original = yaml.safe_load(args.config.read_text())
    validate_config(original)
    snapshot = resolve_model_path(original)
    dataset = ROOT / original["data"]
    if not (dataset / "training-manifest.json").exists():
        raise SystemExit("Build the governed dataset before training")
    adapter = ROOT / original["adapter_path"]
    if args.pilot:
        adapter = adapter.with_name(adapter.name + "-pilot")
    derived = {
        key: value for key, value in original.items()
        if key not in {"revision", "local_model_path"}
    }
    derived["model"] = snapshot
    derived["data"] = str(dataset)
    derived["adapter_path"] = str(adapter)
    if args.pilot:
        derived.update({"iters": 5, "steps_per_report": 1, "steps_per_eval": 5, "save_every": 5, "test": False})
    experiment = Path(original["adapter_path"]).name
    run_dir = ROOT / "reports/runs" / (f"pilot-{experiment}" if args.pilot else experiment)
    run_dir.mkdir(parents=True, exist_ok=True)
    derived_path = run_dir / "resolved-training-config.yaml"
    derived_path.write_text(yaml.safe_dump(derived, sort_keys=False))
    command = [sys.executable, "-m", "mlx_lm", "lora", "--config", str(derived_path)]
    environment = dict(os.environ)
    environment["HF_HOME"] = str(ROOT / ".cache/huggingface")
    with (run_dir / "training.log").open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        assert process.stdout is not None
        for line in process.stdout:
            print(line, end="", flush=True)
            log.write(line)
        return_code = process.wait()
    if return_code:
        raise SystemExit(return_code)
    log_text = (run_dir / "training.log").read_text()
    training_losses = [float(value) for value in re.findall(r"Train loss ([0-9.]+)", log_text)]
    validation_losses = [float(value) for value in re.findall(r"Val loss ([0-9.]+)", log_text)]
    if not training_losses or not validation_losses:
        raise SystemExit("Training completed without required loss and validation evidence")
    reload_generation = reload_smoke(snapshot, adapter)
    files = sorted(path for path in adapter.rglob("*") if path.is_file())
    evidence = {
        "status": "passed", "pilot": args.pilot, "base": original["model"], "baseRevision": original["revision"],
        "config": str(args.config.resolve().relative_to(ROOT)), "adapterPath": str(adapter),
        "trainingLosses": training_losses, "validationLosses": validation_losses,
        "reloadGeneration": reload_generation,
        "files": {str(path.relative_to(adapter)): sha256(path) for path in files},
    }
    (run_dir / "training-evidence.json").write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")
    print(json.dumps(evidence, indent=2))


if __name__ == "__main__":
    main()
