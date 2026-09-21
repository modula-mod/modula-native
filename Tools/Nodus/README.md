# Nodus training and evaluation

This directory is the reproducible, non-runtime tool boundary for Nodus. Python dependencies never enter the Xcode application. Model weights, adapters, caches, generated datasets, and run reports are ignored by Git.

The recorded NODUS-01 environment uses Python 3.14.2 from `.python-version`. `pyproject.toml` pins direct tooling and `reports/python-lock.txt` records the resolved transitive environment. Set `PYTHON_BIN` when the pinned interpreter is not the shell default.

## Reproduce v0.1

```bash
cd Tools/Nodus
./scripts/bootstrap.sh
.venv/bin/python scripts/build_dataset.py
.venv/bin/python -m unittest discover -s tests -v
.venv/bin/python scripts/verify_base_weights.py --config configs/benchmark-qwen3-1.7b.yaml
.venv/bin/python scripts/verify_base_weights.py --config configs/benchmark-smollm2-1.7b.yaml
.venv/bin/python scripts/evaluate.py --config configs/benchmark-qwen3-1.7b.yaml
.venv/bin/python scripts/evaluate.py --config configs/benchmark-smollm2-1.7b.yaml
.venv/bin/python scripts/select_base.py reports/runs/eval-qwen3-1.7b-base.json reports/runs/eval-smollm2-1.7b-base.json
.venv/bin/python scripts/train.py --config configs/nodus-v0.1-qwen3-1.7b-lora.yaml
.venv/bin/python scripts/export_artifact.py --config configs/nodus-v0.1-qwen3-1.7b-lora.yaml
```

`build_dataset.py` rejects missing provenance, training-ineligible records, duplicate content, and semantic groups crossing splits. Held-out eval prompts live under `evals/` and are checked for leakage. `train.py` delegates to the pinned MLX-LM CLI and records immutable run evidence.

Base weights are downloaded outside Git from their exact reviewed revisions. `verify_base_weights.py` requires the recorded byte lengths and upstream LFS SHA-256 digests to match before benchmarking or training.

## Governance

Verification and training consent are separate. A verified correction may create a learning candidate, but only an explicitly approved candidate with valid provenance can enter an approved dataset revision. Generated model artifacts remain `experimental` until all promotion gates pass. Nodus cannot mutate production weights, policies, source code, or approval state.

Base and derivative attribution is recorded in `licenses/base-models.json`. Apache-2.0 requires preserving its license and notices when redistributing a derivative. Public branding may be Nodus, while manifests always retain upstream publisher, model, and exact revision.
