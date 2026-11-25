"""Local asset importer. Requires Blender for non-USDZ inputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import tempfile
import zipfile

FORMATS = (".usdz", ".glb", ".gltf", ".blend", ".fbx", ".obj", ".usd", ".usdc", ".usda", ".dae", ".stl")
LIMIT = 4 * 1024**3

def unpack(source, destination, budget, depth=0):
    if depth > 3:
        raise ValueError("Nested archive depth exceeds limit")
    with zipfile.ZipFile(source) as archive:
        for entry in archive.infolist():
            p = PurePosixPath(entry.filename.replace(chr(92), "/"))
            if not p.parts or p.is_absolute() or ".." in p.parts or ":" in p.parts[0] or stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError("Unsafe archive member")
            target = destination.joinpath(*p.parts)
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            budget[0] -= entry.file_size
            budget[1] -= 1
            if min(budget) < 0:
                raise ValueError("Archive exceeds extraction limits")
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(entry) as inp, target.open("xb") as out:
                shutil.copyfileobj(inp, out)
            if target.suffix.lower() == ".zip":
                nested = target.with_name(target.name + ".contents")
                nested.mkdir()
                unpack(target, nested, budget, depth + 1)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("library", type=Path)
    parser.add_argument("--kind", choices=("body", "hair", "clothing", "accessory", "prop"), required=True)
    parser.add_argument("--model", help="Relative model path for packages containing multiple models")
    parser.add_argument("--blender", default="blender")
    args = parser.parse_args()
    source = args.source.resolve()
    library = args.library.resolve()
    library.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        if source.suffix.lower() == ".zip":
            unpack(source, root, [LIMIT, 20000])
            models = sorted(p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in FORMATS)
            if args.model:
                models = [p for p in models if p.relative_to(root).as_posix() == args.model]
            if len(models) != 1:
                raise ValueError("Select one model with --model: " + json.dumps([p.relative_to(root).as_posix() for p in models]))
            model = models[0]
        else:
            model = source
        if model.suffix.lower() not in FORMATS:
            raise ValueError("Unsupported model format")
        digest = hashlib.sha256()
        with source.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024*1024), b""):
                digest.update(chunk)
        digest.update((args.kind + ":" + (args.model or "")).encode())
        asset_id = digest.hexdigest()[:24]
        destination = library / asset_id
        if destination.exists():
            print(str(destination))
            return
        with tempfile.TemporaryDirectory(dir=library) as staging:
            stage = Path(staging)
            output = stage / "model.usdz"
            if model.suffix.lower() == ".usdz":
                with zipfile.ZipFile(model) as archive:
                    if not any(n.lower().endswith((".usd", ".usda", ".usdc")) for n in archive.namelist()):
                        raise ValueError("Invalid USDZ scene")
                shutil.copyfile(model, output)
            else:
                subprocess.run([args.blender, "--background", "--disable-autoexec", "--python-exit-code", "1",
                    "--python", str(Path(__file__).with_name("export-character.py")), "--",
                    str(model), str(output), "--kind", args.kind], check=True, timeout=900)
            (stage / "asset.json").write_text(json.dumps({"id": asset_id, "name": source.stem,
                "kind": args.kind, "source_format": model.suffix.lower(), "model": "model.usdz"}, indent=2))
            os.rename(stage, destination)
        print(str(destination))

if __name__ == "__main__":
    main()
