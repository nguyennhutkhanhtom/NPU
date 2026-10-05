"""Preserve compact, byte-exact RTL inputs for an immutable timing snapshot.

The optional attention reconstruction only recovers the known pre-fix line
from the preserved signed candidate. Every recovered byte hash must match the
original snapshot; no equivalent-but-different source is accepted.
"""
from pathlib import Path
from hashlib import sha256
from datetime import datetime, timezone
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
import argparse
import json

ROOT = Path(__file__).resolve().parents[2]

def digest(raw):
    return sha256(raw).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--rtl-dir', type=Path, required=True)
    parser.add_argument('--restore-attention-slice', action='store_true')
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    snapshot_path = evidence / 'sources_before.json'
    snapshot = json.loads(snapshot_path.read_text(encoding='utf-8-sig'))
    output = evidence / 'source_archive.zip'
    provenance_path = evidence / 'source_archive.json'
    if output.exists() or provenance_path.exists():
        raise FileExistsError('Source archive already exists; preserve the earlier evidence')
    assets = {}
    restored = []
    for name, expected in snapshot['rtl_sources'].items():
        raw = (args.rtl_dir / name).read_bytes()
        if digest(raw) != expected and args.restore_attention_slice and name == 'llm_soc.sv':
            corrected = b"scalar_product_q <= $signed(scalar_round_q[38:0]) * 25'sd11585"
            original = b"scalar_product_q <= scalar_round_q[38:0] * 25'sd11585"
            if raw.count(corrected) != 1:
                raise ValueError('Preserved candidate does not contain exactly the known corrected line')
            recovered = raw.replace(corrected, original)
            candidates = [recovered, recovered.replace(b'\r\n', b'\n'),
                          recovered.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')]
            matching = [item for item in candidates if digest(item) == expected]
            if not matching:
                raise ValueError('Reconstructed original RTL does not match the pre-build byte hash')
            raw = matching[0]
            restored.append(name)
        if digest(raw) != expected:
            raise ValueError(f'RTL snapshot mismatch: {name}')
        assets['rtl/' + name] = raw
    # Configuration hashes are explicitly canonical LF in the timing manifest.
    for name, expected in snapshot['configuration'].items():
        archived = evidence / name
        raw = (archived if archived.exists() else ROOT/'quartus'/name).read_bytes().replace(b'\r\n', b'\n')
        if digest(raw) != expected:
            raise ValueError(f'Configuration snapshot mismatch: {name}')
        assets['quartus/' + name] = raw
    with ZipFile(output, 'w', compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for name, raw in sorted(assets.items()):
            entry = ZipInfo(name, date_time=(1980,1,1,0,0,0))
            entry.compress_type = ZIP_DEFLATED
            archive.writestr(entry, raw, compresslevel=9)
    provenance = {
        'archived_at_utc': datetime.now(timezone.utc).isoformat(),
        'archive_sha256': digest(output.read_bytes()),
        'snapshot_sha256': digest(snapshot_path.read_bytes()),
        'source_directory': str(args.rtl_dir.resolve()),
        'restored_pre_fix_assets': restored,
        'verification': 'All RTL byte hashes equal original pre-build snapshot; configurations use recorded canonical LF hashes',
        'files': {name: digest(raw) for name, raw in assets.items()},
    }
    provenance_path.write_text(json.dumps(provenance, indent=2)+'\n', encoding='utf-8', newline='\n')
    print(f'SOURCE_ARCHIVE_PASS assets={len(assets)} bytes={output.stat().st_size} restored={restored}')

if __name__ == '__main__':
    main()
