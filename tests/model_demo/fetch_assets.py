"""Fetch pinned demo inputs and reject content that does not match SHA-256."""
from hashlib import sha256
from pathlib import Path
import argparse
import json
import urllib.request

ROOT = Path(__file__).resolve().parent
HISTORICAL = {
    "BitNetMCU.py": "7df26fc7ef6be83eddbd432463f52fccdab2f2853e6adf3f7ab5234bd00e6e4a",
    "test_inference.py": "d99c767d06cfa5e9df09d00c9d62894d67b16ed3b6216d626c91812814f6750a",
    "training.py": "979081c7b5776e65ceb39c5fa3ccb3b31c1abb33ab404ca6cdfbae15168a5ebb",
}


def assets():
    manifest = json.loads((ROOT / "upstream_manifest.json").read_text(encoding="utf-8-sig"))
    history = json.loads((ROOT / "checkpoint_history.json").read_text(encoding="utf-8-sig"))
    entries = [dict(item) for item in manifest["files"]]
    for name, digest in HISTORICAL.items():
        entries.append({
            "local": f"historical_{name}",
            "url": f"https://raw.githubusercontent.com/cpldcpu/BitNetMCU/{history['checkpoint_commit']}/{name}",
            "sha256": digest,
        })
    for entry in entries:
        name = entry["local"]
        if name != Path(name).name or "/" in name or "\\" in name:
            raise ValueError(f"Invalid asset filename: {name}")
        if not entry["url"].startswith("https://raw.githubusercontent.com/cpldcpu/BitNetMCU/"):
            raise ValueError(f"Unexpected upstream URL: {entry['url']}")
    return entries


def verify(data, entry):
    if "bytes" in entry and len(data) != entry["bytes"]:
        raise ValueError(f"Size mismatch: {entry['local']}")
    if sha256(data).hexdigest() != entry["sha256"]:
        raise ValueError(f"SHA-256 mismatch: {entry['local']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify local assets without network access.")
    args = parser.parse_args()
    destination = ROOT / "upstream"
    entries = assets()
    if not args.check:
        destination.mkdir(exist_ok=True)
    for entry in entries:
        target = destination / entry["local"]
        if target.is_file():
            try:
                verify(target.read_bytes(), entry)
                continue
            except ValueError:
                if args.check:
                    raise
        elif args.check:
            raise FileNotFoundError(f"Missing asset: {target.name}")
        request = urllib.request.Request(entry["url"], headers={"User-Agent": "NPU-demo-asset-fetcher"})
        with urllib.request.urlopen(request, timeout=45) as response:
            data = response.read(2_000_001)
        if len(data) > 2_000_000:
            raise ValueError(f"Unexpectedly large asset: {entry['local']}")
        verify(data, entry)
        temporary = target.with_name(target.name + ".download")
        temporary.write_bytes(data)
        temporary.replace(target)
        print(f"Fetched {target.name}")
    print(f"MNIST_ASSETS_PASS: {len(entries)} pinned files verified")


if __name__ == "__main__":
    main()
