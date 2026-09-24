from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


MANIFEST_NAME = "nodus-r7-experimental.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def tree_hash(files: dict[str, str]) -> str:
    canonical = "".join(
        f"{relative_path}\0{files[relative_path]}\n"
        for relative_path in sorted(files)
    ).encode()
    return hashlib.sha256(canonical).hexdigest()


def verify(manifest_path: Path, model_directory: Path) -> dict:
    expected = json.loads(manifest_path.read_text())
    cached_manifest_path = model_directory / MANIFEST_NAME
    if not cached_manifest_path.is_file():
        raise ValueError(f"missing {MANIFEST_NAME}")
    cached = json.loads(cached_manifest_path.read_text())
    if cached != expected:
        raise ValueError("cached experimental manifest does not match the tracked manifest")
    if expected.get("stage") != "experimentalCandidate" or expected.get("shippingAllowed") is not False:
        raise ValueError("experimental stage or production-exclusion policy is invalid")
    if expected.get("providerID") != "modula.nodus" or expected.get("runtimeFormat") != "mlx":
        raise ValueError("unsupported provider or runtime format")

    expected_files = expected.get("files")
    if not isinstance(expected_files, dict) or not expected_files:
        raise ValueError("manifest has no runtime files")
    actual_paths = {
        str(path.relative_to(model_directory))
        for path in model_directory.rglob("*")
        if path.is_file() and path.name != MANIFEST_NAME
    }
    if actual_paths != set(expected_files):
        difference = sorted(actual_paths.symmetric_difference(expected_files))
        raise ValueError(f"runtime file set mismatch: {difference}")
    for relative_path, expected_hash in expected_files.items():
        path = model_directory / relative_path
        if path.is_symlink():
            raise ValueError(f"symbolic link rejected: {relative_path}")
        actual_hash = sha256(path)
        if actual_hash != expected_hash:
            raise ValueError(f"SHA-256 mismatch: {relative_path}")
    if tree_hash(expected_files) != expected.get("quantizedSHA256"):
        raise ValueError("quantized artifact SHA-256 mismatch")
    return expected


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify the cached Nodus developer candidate")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--model-directory", type=Path, required=True)
    args = parser.parse_args()
    manifest = verify(args.manifest.resolve(), args.model_directory.resolve())
    print(
        f"verified {manifest['displayName']} "
        f"({manifest['quantizedSHA256']})"
    )


if __name__ == "__main__":
    main()
