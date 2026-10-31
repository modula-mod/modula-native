#!/usr/bin/env python3
"""Series 2 on-demand pack sources.

Writes (or checks) Tools/moliboo/packages/series2/. These files are the pack
source tree. They are not copied into the app bundle.

Each character directory holds:
  character.json  — declarative patch (modula.moliboo.character.1), no wardrobe fit
  portrait.png    — the complete 640×640 transparent PNG, byte-for-byte
  source.svg      — the complete 320×320 SVG, kept beside the pack (the signed
                    container allows json and png only, so the SVG is not packed)

Greenfield's HTTP atlas has no Moliboo or marketplace route. This script does
not sign packages and does not invent a signature. Sign later with
publish_qa_package.mjs --portrait portrait.png when MODULA_SIGNING_KEY_PATH is set.

Usage:
  build_series2_sources.py <repo-root> --check
  build_series2_sources.py <repo-root> --from-zip <zip>   # one-time import
"""
import hashlib, json, re, struct, sys, zipfile
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
CHECK = "--check" in sys.argv
ZIP = None
if "--from-zip" in sys.argv:
    ZIP = Path(sys.argv[sys.argv.index("--from-zip") + 1])

OUT = ROOT / "Tools/moliboo/packages/series2"
SOURCES = OUT / "sources"
REGISTRY = ROOT / "ios/Modula/Resources/Moliboo/moliboo_registry.json"
ACCENTS = ROOT / "Tools/moliboo/registry/series2/accents.json"
MANIFEST = OUT / "manifest.json"
IEND = bytes.fromhex("0000000049454e44ae426082")
PNG_SIG = bytes.fromhex("89504e470d0a1a0a")


def sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def fail(msg: str) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(1)


def png_ok(b: bytes) -> tuple[int, int]:
    if len(b) < 32 or not b.startswith(PNG_SIG) or not b.endswith(IEND):
        fail("portrait is not a complete PNG")
    w, h = struct.unpack(">II", b[16:24])
    if (w, h) != (640, 640):
        fail(f"portrait is {w}×{h}, expected the full 640×640 image")
    return w, h


def svg_ok(text: str) -> None:
    if not text.startswith("<svg ") or not text.rstrip().endswith("</svg>"):
        fail("SVG is truncated or not a complete document")
    if 'width="320"' not in text or 'height="320"' not in text or 'viewBox="0 0 320 320"' not in text:
        fail("SVG is not the full 320×320 canvas")
    if "<text" in text or ".." in text:
        fail("SVG contains text or a suspicious path")


def load_registry():
    reg = json.loads(REGISTRY.read_text())
    accents = json.loads(ACCENTS.read_text())
    drafts = [c for c in reg["characters"] if c["availability"] == "draft"]
    if [c["number"] for c in drafts] != list(range(116, 216)):
        fail("registry drafts are not #116–215")
    return reg, drafts, accents


def patch_for(c: dict, accents: dict) -> dict:
    concept = int(c["conceptId"].rsplit(".", 1)[1])
    colour = accents[str(concept)]
    return {
        "schemaVersion": "modula.moliboo.character.1",
        "characterId": c["id"],
        "key": c["key"],
        "assetVersion": c["assetVersion"],
        "palette": {
            "mid": colour["mid"],
            "accent": colour["light"],
            "light": colour["light"],
            "dark": colour["deep"],
        },
        "form": c["personality"]["description"],
    }


def safe_name(c: dict) -> str:
    name = f"{c['number']:03d}_{c['key']}"
    if not re.fullmatch(r"[0-9]{3}_[a-z0-9]+", name):
        fail(f"unsafe directory name {name}")
    return name


def import_zip(drafts, accents) -> None:
    if ZIP is None or not ZIP.is_file():
        fail("pass --from-zip <path> to import artwork")
    with zipfile.ZipFile(ZIP) as zf:
        names = set(zf.namelist())
        for c in drafts:
            concept = int(c["conceptId"].rsplit(".", 1)[1])
            png_member = f"genesis/Moliboo_Genesis_101-200/png/{concept}_{c['key']}.png"
            svg_member = f"genesis/Moliboo_Genesis_101-200/svg/{concept}_{c['key']}.svg"
            # Members are built from registry fields, never from zip path strings.
            if png_member not in names or svg_member not in names:
                fail(f"missing artwork for {c['key']}")
            if ".." in png_member or png_member.startswith("/"):
                fail(png_member)
            dest = SOURCES / safe_name(c)
            dest.mkdir(parents=True, exist_ok=True)
            png = zf.read(png_member)
            svg = zf.read(svg_member)
            png_ok(png)
            svg_ok(svg.decode())
            (dest / "portrait.png").write_bytes(png)
            (dest / "source.svg").write_bytes(svg)
            (dest / "character.json").write_text(json.dumps(patch_for(c, accents), indent=2) + "\n")
    write_manifest(drafts)


def file_record(path: Path, media: str, extra: dict) -> dict:
    data = path.read_bytes()
    rec = {"path": path.name, "mediaType": media, "sha256": sha256(data), "bytes": len(data)}
    rec.update(extra)
    return rec


def write_manifest(drafts) -> None:
    packages = []
    for c in drafts:
        folder = SOURCES / safe_name(c)
        png = (folder / "portrait.png").read_bytes()
        svg = (folder / "source.svg").read_text()
        png_ok(png)
        svg_ok(svg)
        patch = json.loads((folder / "character.json").read_text())
        expect = patch_for(c, json.loads(ACCENTS.read_text()))
        if patch != expect:
            fail(f"{c['key']} character.json does not match the registry")
        if "fit" in patch:
            fail(f"{c['key']} must not declare a wardrobe fit")
        packages.append({
            "packageId": c["packageId"],
            "version": c["assetVersion"],
            "characterId": c["id"],
            "key": c["key"],
            "familyId": c["familyId"],
            "number": c["number"],
            "conceptId": c["conceptId"],
            "availability": "draft",
            "purchasable": False,
            "signed": False,
            "directory": f"sources/{safe_name(c)}",
            "containerFiles": ["character.json", "portrait.png"],
            "files": [
                file_record(folder / "character.json", "application/json", {}),
                file_record(folder / "portrait.png", "image/png", {"width": 640, "height": 640}),
                file_record(folder / "source.svg", "image/svg+xml", {"width": 320, "height": 320, "packed": False}),
            ],
        })
    manifest = {
        "schemaVersion": "modula.moliboo.series2-sources.1",
        "availability": "draft",
        "purchasable": False,
        "distribution": "on-demand",
        "backend": "none — the Greenfield HTTP atlas has no Moliboo or marketplace route",
        "signing": "unsigned sources; publish_qa_package.mjs --portrait portrait.png signs when MODULA_SIGNING_KEY_PATH is set",
        "packages": packages,
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")


def check() -> None:
    reg, drafts, accents = load_registry()
    if not MANIFEST.is_file():
        fail("series2 manifest.json is missing")
    manifest = json.loads(MANIFEST.read_text())
    if manifest.get("schemaVersion") != "modula.moliboo.series2-sources.1":
        fail("unexpected manifest schema")
    if manifest.get("purchasable") is not False or manifest.get("signed") is True:
        fail("manifest must stay unsigned and not purchasable")
    by_id = {p["packageId"]: p for p in manifest["packages"]}
    if len(by_id) != 100:
        fail(f"expected 100 packages, found {len(by_id)}")
    pbx = (ROOT / "ios/Modula.xcodeproj/project.pbxproj").read_text()
    if "series2/sources" in pbx or "portrait.png" in pbx:
        fail("Series 2 portraits must not be members of the app target")
    bundled = list((ROOT / "ios/Modula").rglob("portrait.png"))
    if bundled:
        fail(f"portrait.png is inside the app tree: {bundled[0]}")
    for c in drafts:
        name = safe_name(c)
        folder = SOURCES / name
        pkg = by_id.get(c["packageId"])
        if pkg is None:
            fail(f"manifest missing {c['packageId']}")
        if pkg["number"] != c["number"] or pkg["key"] != c["key"] or pkg["conceptId"] != c["conceptId"]:
            fail(f"{c['key']} manifest does not match the registry")
        if pkg["availability"] != "draft" or pkg["purchasable"] is not False or pkg["signed"] is not False:
            fail(f"{c['key']} must stay an unsigned draft")
        if pkg["directory"] != f"sources/{name}" or ".." in pkg["directory"]:
            fail(f"{c['key']} has an unsafe directory")
        if pkg["containerFiles"] != ["character.json", "portrait.png"]:
            fail(f"{c['key']} container file list changed")
        expect_patch = patch_for(c, accents)
        on_disk = json.loads((folder / "character.json").read_text())
        if on_disk != expect_patch or "fit" in on_disk:
            fail(f"{c['key']} character.json drifted")
        for rec in pkg["files"]:
            rel = rec["path"]
            if rel != Path(rel).name or rel.startswith("."):
                fail(f"unsafe file path {rel}")
            blob = (folder / rel).read_bytes()
            if sha256(blob) != rec["sha256"] or len(blob) != rec["bytes"]:
                fail(f"{c['key']} {rel} digest or size does not match the manifest")
            if rel == "portrait.png":
                png_ok(blob)
                if rec.get("width") != 640 or rec.get("height") != 640:
                    fail(f"{c['key']} portrait dimensions are not 640")
            if rel == "source.svg":
                svg_ok(blob.decode())
                if rec.get("packed") is not False:
                    fail("SVG must stay out of the signed container")
    print(f"series 2 pack sources ok ({len(drafts)} drafts, unsigned, not bundled)")


def main() -> None:
    _, drafts, accents = load_registry()
    if CHECK:
        check()
        return
    if ZIP is None:
        fail("pass --check or --from-zip")
    import_zip(drafts, accents)
    check()


if __name__ == "__main__":
    main()
