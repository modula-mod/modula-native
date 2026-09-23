from __future__ import annotations

import json
import random
from collections import Counter
from pathlib import Path

from common import ROOT, read_jsonl, sha256, write_jsonl


PROFILES = {
    "freshness": {"taskModes": {"CLASSIFY_FRESHNESS"}, "categories": None, "limit": None},
    "abstention": {"taskModes": {"SHOULD_ABSTAIN"}, "categories": None, "limit": None},
    "modula": {
        "taskModes": {"MODULA_ANSWER"},
        "categories": {
            "MODULA_KNOWLEDGE", "MODULA_ARCHITECTURE", "MODULE_KNOWLEDGE",
            "CAPABILITY_SELECTION", "LOCAL_INTELLIGENCE", "NODUS", "GAIA", "AKI", "GOVERNOR",
            "AUTHORITY_BOUNDARIES",
        },
        "limit": {"train": 700, "valid": 160, "test": 160},
    },
}


def main() -> None:
    source = ROOT / "data/generated/nodus-training-v0.2"
    for profile, selection in PROFILES.items():
        output = ROOT / f"data/generated/nodus-01c-micro-{profile}"
        output.mkdir(parents=True, exist_ok=True)
        counts = {}
        mode_counts: Counter = Counter()
        files = {}
        for split in ("train", "valid", "test"):
            records = [
                item for item in read_jsonl(source / f"{split}.jsonl")
                if item["metadata"].get("taskMode") in selection["taskModes"]
                and (selection["categories"] is None or item["metadata"]["category"] in selection["categories"])
            ]
            random.Random(101 + len(profile) + len(split)).shuffle(records)
            limit = selection["limit"] and selection["limit"][split]
            if limit:
                records = records[:limit]
            if not records:
                raise ValueError(f"{profile}/{split}: empty micro split")
            write_jsonl(output / f"{split}.jsonl", records)
            counts[split] = len(records)
            mode_counts.update(item["metadata"]["taskMode"] for item in records)
            files[split] = sha256(output / f"{split}.jsonl")
        manifest = {
            "schemaVersion": 1,
            "datasetRevision": f"nodus-01c-micro-{profile}",
            "parentRevision": "nodus-training-v0.2",
            "approvalState": "approved-for-experiment",
            "splitCounts": counts,
            "taskModeDistribution": dict(sorted(mode_counts.items())),
            "files": files,
        }
        (output / "training-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        print(json.dumps(manifest, sort_keys=True))


if __name__ == "__main__":
    main()
