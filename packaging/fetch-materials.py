import json, pathlib, sys, urllib.request, zipfile, io

out = pathlib.Path(sys.argv[1])
def get(url):
    with urllib.request.urlopen(url, timeout=90) as response:
        return response.read()
def save(folder, name, data):
    if not data.startswith(b'\xff\xd8'):
        raise ValueError("Expected JPEG for " + name)
    (folder / (name + ".jpg")).write_bytes(data)
for folder_name, asset in [("walnut", "american_walnut_veneer"), ("ash", "ash_veneer"), ("oak", "black_oak_veneer")]:
    folder = out / folder_name
    folder.mkdir(parents=True, exist_ok=True)
    maps = json.loads(get("https://api.polyhaven.com/files/" + asset))
    for name, key in [("color", "diff"), ("normal", "nor_gl"), ("roughness", "rough")]:
        save(folder, name, get(maps[key]["1k"]["jpg"]["url"]))
    (folder / "SOURCE.txt").write_text("CC0 - https://polyhaven.com/a/" + asset + "\n")
folder = out / "flooring"
folder.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(io.BytesIO(get("https://ambientcg.com/get?file=WoodFloor051_1K-JPG.zip"))) as archive:
    for name, suffix in [("color", "_Color.jpg"), ("normal", "_NormalGL.jpg"), ("roughness", "_Roughness.jpg")]:
        entry = next(x for x in archive.namelist() if x.endswith(suffix))
        if archive.getinfo(entry).file_size > 20 * 1024 * 1024:
            raise ValueError("Unexpected texture size")
        save(folder, name, archive.read(entry))
(folder / "SOURCE.txt").write_text("CC0 - https://ambientcg.com/view?id=WoodFloor051\n")
