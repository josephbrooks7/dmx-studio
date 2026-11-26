#!/usr/bin/env python3
"""Inspect locally downloaded character packages without changing the originals.

Run from the repository root:
  python3 packaging/prepare-character-assets.py --downloads ~/Downloads --backup ~/Downloads/DMX\ Studio\ Asset\ Backup
Optional:
  python3 packaging/prepare-character-assets.py --downloads ~/Downloads --blender /Applications/Blender.app/Contents/MacOS/Blender --convert realistic_male_character.glb --kind body --license "LICENSE IDENTIFIER" --source "SOURCE URL"

Conversion requires explicit provenance. Review permissions before distributing
assets through GitHub or DMX Studio releases.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile

EXT = {".glb", ".gltf", ".fbx", ".obj", ".blend", ".usdz", ".usd", ".usda", ".usdc"}
KIND = ("body", "hair", "clothing", "accessory", "prop")


def inspect_archive(path):
    with zipfile.ZipFile(path) as z:
        members = [x for x in z.infolist() if not x.is_dir()]
        models = [x.filename for x in members if Path(x.filename).suffix.lower() in EXT]
        return {"models": models[:30], "model_count": len(models),
                "size_unpacked": sum(x.file_size for x in members)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--downloads", type=Path, default=Path.home() / "Downloads")
    ap.add_argument("--backup", type=Path, help="Optional second folder containing downloaded asset backups")
    ap.add_argument("--convert", help="Exact filename of one model/archive from the scanned folders")
    ap.add_argument("--model", help="Model path inside an archive if it contains multiple 3D models")
    ap.add_argument("--kind", choices=KIND)
    ap.add_argument("--license", help="Verified redistribution license for this model")
    ap.add_argument("--source", help="Original asset source URL")
    ap.add_argument("--blender", default="/Applications/Blender.app/Contents/MacOS/Blender")
    ap.add_argument("--output", type=Path, default=Path("packaging/character-library"))
    args = ap.parse_args()
    locations = [args.downloads.expanduser()]
    if args.backup:
        locations.append(args.backup.expanduser())
    candidates = {}
    for folder in locations:
        if not folder.is_dir():
            print("Skipping missing directory:", folder, file=sys.stderr)
            continue
        for path in sorted(folder.rglob("*")):
            if not path.is_file() or path.suffix.lower() not in EXT | {".zip"}:
                continue
            # Keep output and unrelated archive listings readable.
            try:
                details = inspect_archive(path) if path.suffix.lower() == ".zip" else {"models": [path.name], "model_count": 1}
            except (OSError, zipfile.BadZipFile) as exc:
                details = {"error": str(exc)}
            key = path.name.casefold()
            candidates.setdefault(key, []).append(path)
            print(json.dumps({"name": path.name, "path": str(path), **details}))
    if not args.convert:
        print("Scan complete. No assets changed, converted, or committed.")
        return
    choices = candidates.get(Path(args.convert).name.casefold(), [])
    if len(choices) != 1:
        raise SystemExit("Expected exactly one matching source; matches: " + str([str(p) for p in choices]))
    if not all((args.kind, args.license, args.source)):
        raise SystemExit("Conversion requires --kind, --license and --source (verify redistribution rights first)")
    if not Path(args.blender).is_file():
        raise SystemExit("Blender not found at: " + args.blender)
    source = choices[0]
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    command = [sys.executable, "packaging/import-asset.py", str(source), str(out),
               "--kind", args.kind, "--blender", args.blender]
    if args.model:
        command += ["--model", args.model]
    subprocess.run(command, check=True)
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    report = out / "import-provenance.jsonl"
    with report.open("a", encoding="utf-8") as f:
        f.write(json.dumps({"original": str(source), "sha256": source_hash,
                            "kind": args.kind, "license": args.license,
                            "source": args.source}) + "\n")
    print("Converted into staging. Review model and licensing before committing binary to the shipping manifest.")

if __name__ == "__main__":
    main()
