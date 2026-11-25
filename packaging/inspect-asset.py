"""Inspect asset packages without executing or extracting their contents."""
import argparse
import json
from pathlib import Path, PurePosixPath
import zipfile

FORMATS = (".usdz", ".glb", ".gltf", ".blend", ".fbx", ".obj", ".usd", ".usdc", ".usda", ".dae", ".stl")
TEXTURES = {".png", ".jpg", ".jpeg", ".tga", ".exr", ".webp", ".tif", ".tiff"}
def inspect(path):
    path = Path(path)
    if path.is_dir():
        names = [p.relative_to(path).as_posix() for p in path.rglob("*") if p.is_file() and not p.is_symlink()]
    elif path.suffix.lower() == ".zip":
        with zipfile.ZipFile(path) as archive:
            names = []
            for entry in archive.infolist():
                name = entry.filename.replace(chr(92), "/")
                p = PurePosixPath(name)
                if p.is_absolute() or ".." in p.parts or ":" in p.parts[0]:
                    raise ValueError("Unsafe archive member: " + name)
                if not entry.is_dir():
                    names.append(name)
    else:
        names = [path.name]
    models = []
    textures = []
    nested = []
    unsupported = []
    for name in names:
        ext = PurePosixPath(name).suffix.lower()
        if ext in FORMATS:
            models.append({"path": name, "format": ext[1:]})
        elif ext in TEXTURES:
            textures.append(name)
        elif ext == ".zip":
            nested.append(name)
        elif ext == ".max":
            unsupported.append(name)
    models.sort(key=lambda m: (FORMATS.index("." + m["format"]), m["path"].lower()))
    return {"source": str(path), "models": models, "textures": sorted(textures),
            "nested_archives": sorted(nested), "requires_external_conversion": sorted(unsupported),
            "requires_selection": len(models) != 1}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    args = parser.parse_args()
    print(json.dumps(inspect(args.source), indent=2))
