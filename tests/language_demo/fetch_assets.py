"""Download pinned public assets and verify the recorded SHA256 before use."""
from hashlib import sha256
from pathlib import Path
import argparse
import json
import urllib.request

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    manifest = json.loads((ROOT / "upstream_manifest.json").read_text())
    for name, expected in manifest["files"].items():
        path = ROOT / "upstream" / name
        if not args.check and (not path.exists() or sha256(path.read_bytes()).hexdigest() != expected["sha256"]):
            if name.startswith("nanofable/"):
                url = f"https://raw.githubusercontent.com/adit-rah/nanofable/{manifest['source_revision']}/src/{name}"
            else:
                url = f"https://huggingface.co/adrahmana/NanoFable-1M-ternary/resolve/{manifest['model_revision']}/{name}"
            request = urllib.request.Request(url, headers={"User-Agent": "portable-npu-language-demo"})
            data = urllib.request.urlopen(request, timeout=90).read()
            if len(data) != expected["bytes"] or sha256(data).hexdigest() != expected["sha256"]:
                raise ValueError(f"Downloaded asset hash mismatch: {name}")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        if not path.is_file() or path.stat().st_size != expected["bytes"] or sha256(path.read_bytes()).hexdigest() != expected["sha256"]:
            raise ValueError(f"Missing or changed pinned asset: {name}")
    print(f"LANGUAGE_ASSETS_PASS {len(manifest['files'])} pinned files")


if __name__ == "__main__":
    main()
