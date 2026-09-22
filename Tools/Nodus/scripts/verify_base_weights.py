from __future__ import annotations

import argparse
import json
from pathlib import Path

import yaml

from common import ROOT, sha256


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify revision-pinned base weights against Hub LFS digests")
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    config = yaml.safe_load(args.config.read_text())
    catalog = json.loads((ROOT / "licenses/base-models.json").read_text())
    entry = next(
        (
            item for item in catalog["models"]
            if item["model"] == config["model"] and item["revision"] == config["revision"]
        ),
        None,
    )
    if entry is None:
        raise SystemExit("The configured model and revision are not in the reviewed license catalog")
    directory = (ROOT / config["local_model_path"]).resolve()
    verified: list[dict] = []
    for expected in entry["weightFiles"]:
        path = directory / expected["path"]
        if not path.is_file():
            raise SystemExit(f"Missing weight: {path}")
        actual_bytes = path.stat().st_size
        if actual_bytes != expected["bytes"]:
            raise SystemExit(f"Size mismatch for {expected['path']}: {actual_bytes} != {expected['bytes']}")
        actual_hash = sha256(path)
        if actual_hash != expected["sha256"]:
            raise SystemExit(f"SHA-256 mismatch for {expected['path']}")
        verified.append({"path": expected["path"], "bytes": actual_bytes, "sha256": actual_hash})
    print(json.dumps({
        "status": "passed", "model": entry["model"], "revision": entry["revision"], "weights": verified,
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
