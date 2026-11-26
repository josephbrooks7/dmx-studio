#!/usr/bin/env python3
"""Read-only inventory of male/female head archives for Character Studio.

Does not extract, convert, upload, or import assets. Recursive ZIP inspection
is limited to two nested layers and 64 MiB per nested archive. Unknown licenses
are NOT permission to redistribute assets.
"""
from __future__ import annotations

import hashlib
import io
from pathlib import Path
import zipfile

SOURCES = (
    "male-head-textured.zip",
    "realistic-female-head-study.zip",
)
MODEL_EXTENSIONS = {".fbx", ".obj", ".glb", ".gltf", ".blend", ".usd", ".usdz", ".dae"}
TEXTURE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".tif", ".tiff", ".exr", ".webp"}
LICENSE_NAMES = {"license", "licence", "readme", "copyright", "attribution"}
NESTED_LIMIT = 64 * 1024 * 1024


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inspect_zip(archive: zipfile.ZipFile, prefix: str = "", depth: int = 0) -> None:
    for member in archive.infolist():
        if member.is_dir():
            continue
        name = member.filename
        ext = Path(name).suffix.lower()
        lowname = Path(name).name.lower()
        if ext in MODEL_EXTENSIONS:
            kind = "MODEL"
        elif ext in TEXTURE_EXTENSIONS:
            kind = "TEXTURE"
        elif any(label in lowname for label in LICENSE_NAMES):
            kind = "POTENTIAL LICENSE/README"
        elif ext == ".zip":
            kind = "NESTED ZIP"
        else:
            kind = "OTHER"
        print(f"  {kind:24} {member.file_size:>12,} bytes  {prefix}{name}")
        if ext == ".zip" and depth < 2:
            if member.file_size > NESTED_LIMIT:
                print("    Skipping oversized nested archive")
                continue
            try:
                with archive.open(member) as source:
                    data = source.read(NESTED_LIMIT + 1)
                if len(data) > NESTED_LIMIT:
                    print("    Skipping oversized nested archive")
                    continue
                with zipfile.ZipFile(io.BytesIO(data)) as nested:
                    inspect_zip(nested, prefix=prefix + name + "::", depth=depth + 1)
            except (OSError, zipfile.BadZipFile, RuntimeError, ValueError) as exc:
                print(f"    Could not inspect nested archive: {exc}")


def main() -> None:
    folder = Path.home() / "Downloads"
    for name in SOURCES:
        path = folder / name
        print(f"\n=== {name} ===")
        if not path.is_file():
            print(f"Missing: {path}")
            continue
        print(f"SHA-256: {file_hash(path)}")
        try:
            with zipfile.ZipFile(path) as archive:
                inspect_zip(archive)
        except (OSError, zipfile.BadZipFile) as exc:
            print(f"Could not inspect archive: {exc}")
    print("\nNo files extracted or uploaded. Source licensing still requires verification.")


if __name__ == "__main__":
    main()
