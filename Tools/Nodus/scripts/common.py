from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any, Iterable

from huggingface_hub import snapshot_download

ROOT = Path(__file__).resolve().parents[1]


class GovernanceError(ValueError):
    pass


def resolve_model_path(config: dict[str, Any]) -> str:
    """Prefer a revision-pinned local snapshot, otherwise use the Hub cache."""
    local = config.get("local_model_path")
    if local:
        directory = (ROOT / local).resolve()
        index_path = directory / "model.safetensors.index.json"
        single_path = directory / "model.safetensors"
        if index_path.exists():
            index = json.loads(index_path.read_text())
            required = {directory / name for name in index.get("weight_map", {}).values()}
            if required and all(path.exists() for path in required):
                return str(directory)
        elif single_path.exists():
            return str(directory)
    return snapshot_download(
        repo_id=config["model"],
        revision=config["revision"],
        cache_dir=ROOT / ".cache/huggingface",
    )


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def sha256(value: bytes | str | Path) -> str:
    digest = hashlib.sha256()
    if isinstance(value, Path):
        with value.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    else:
        digest.update(value.encode() if isinstance(value, str) else value)
    return digest.hexdigest()


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as error:
                raise GovernanceError(f"{path}:{line_number}: invalid JSON: {error}") from error
            if not isinstance(record, dict):
                raise GovernanceError(f"{path}:{line_number}: object required")
            records.append(record)
    return records


def write_jsonl(path: Path, records: Iterable[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, sort_keys=True, ensure_ascii=False) + "\n")


def normalize(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def validate_example(record: dict[str, Any], known_sources: set[str]) -> dict[str, Any]:
    required = {
        "id", "semanticGroup", "category", "prompt", "response", "source",
        "sourceRevision", "license", "creationMethod", "privacyClass", "trainingEligibility",
    }
    missing = sorted(required - record.keys())
    if missing:
        raise GovernanceError(f"{record.get('id', '<unknown>')}: missing {', '.join(missing)}")
    if record["source"] not in known_sources:
        raise GovernanceError(f"{record['id']}: unknown source {record['source']}")
    if record["trainingEligibility"] != "approved":
        raise GovernanceError(f"{record['id']}: only approved examples may enter a training revision")
    if record["privacyClass"] in {"personal", "private", "secret", "production-user-data"}:
        raise GovernanceError(f"{record['id']}: prohibited privacy class")
    if not str(record["prompt"]).strip() or not str(record["response"]).strip():
        raise GovernanceError(f"{record['id']}: prompt and response must be non-empty")
    enriched = dict(record)
    content = {"prompt": record["prompt"], "response": record["response"]}
    enriched["contentHash"] = "sha256:" + sha256(canonical_json(content))
    enriched["createdAt"] = record.get("createdAt", "2026-09-20T00:00:00Z")
    return enriched


def validate_learning_candidate(record: dict[str, Any]) -> None:
    if record.get("trainingEligibility") != "approved":
        raise GovernanceError("learning candidate is not explicitly approved")
    if record.get("verification", {}).get("schemaValid") is not True:
        raise GovernanceError("verified-result schema has not been validated")
    if record.get("verification", {}).get("provenanceValid") is not True:
        raise GovernanceError("verified-result provenance is invalid")
    if record.get("verification", {}).get("result") not in {"corrected", "partially_correct", "stale"}:
        raise GovernanceError("candidate is not backed by a corrective verification result")
    if record.get("globalTrainingConsent") is not True:
        raise GovernanceError("verification is not global training consent")
    if record.get("privacyClass") in {"personal", "private", "secret", "production-user-data"}:
        raise GovernanceError("private candidate cannot enter the global corpus")
