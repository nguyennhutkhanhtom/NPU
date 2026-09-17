"""Report only current build results and preserve reproducible evidence."""
from pathlib import Path
import json,hashlib,re,sys
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/"functional"
SIM=OUT/"sim"
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
build=json.loads((SIM/"build.json").read_text(encoding="utf-8-sig"))
changed=[name for name,digest in build["sources"].items() if sha(ROOT/name)!=digest]
tests={}
for group in ("alu","storage","norm","ternary","ddr","core","control"):
    for width in (8,16):
        name=f"tb_{group}-{width}.log";p=SIM/name
        log=p.read_text(encoding="utf-8-sig",errors="replace") if p.exists() else ""
        marker=re.search(r"^# "+group.upper()+r"_PASS[^\r\n]*",log,re.M)
        fresh=p.exists() and p.stat().st_mtime >= (SIM/"build.json").stat().st_mtime
        good=bool(marker) and not re.search(r"^# \*\* (Fatal|Error):",log,re.M) and fresh
        tests[name]={"status":"PASS" if good else "NOT_VERIFIED","marker":marker[0][2:] if marker else None}
for width in (8,16):
    for case in range(10):
        p=SIM/f"guard-{width}-{case}.log"
        log=p.read_text(encoding="utf-8-sig",errors="replace") if p.exists() else ""
        fresh=p.exists() and p.stat().st_mtime >= (SIM/"build.json").stat().st_mtime
        good=f"GUARD_EXPECTED_PASS W={width} CASE={case}" in log and "GUARD_MISSED" not in log and fresh
        tests[p.name]={"status":"PASS" if good else "NOT_VERIFIED","scope":"Expected invalid configuration/missing-file rejection"}
assets=json.loads((OUT/"assets/manifest.json").read_text())
assets_ok=all(sha(OUT/"assets"/name)==digest for name,digest in assets.items())
baseline=json.loads((ROOT/"scale/baseline/manifest.json").read_text(encoding="utf-8-sig"))
baseline_ok=all(sha(ROOT/"scale/baseline"/Path(item["Path"]).name)==item["Hash"].lower() for item in baseline)
summary={
    "scope":"Functional fixes, supported Q4.4 and Q4.12 profiles",
    "status":"PASS" if not changed and assets_ok and baseline_ok and all(t["status"]=="PASS" for t in tests.values()) else "NOT_VERIFIED",
    "tests":tests,"sources_changed_since_build":changed,"assets_sha256_verified":assets_ok,
    "original_baseline_unchanged":baseline_ok,"rtl_sha256":{p.name:sha(p) for p in sorted((ROOT/"Verilog Source code").iterdir()) if p.suffix in (".sv",".v")},
    "limits":["No synthesis, timing closure, FPGA or real MIG IP validation.",
              "Generated LUTs and test program are numeric validation assets, not original trained model assets.",
              "Simulation regression is not a proof that all possible bugs are absent."]
}
(OUT/"verification.json").write_text(json.dumps(summary,indent=2)+"\n",encoding="utf-8")
print(json.dumps({"status":summary["status"],"passed":sum(v["status"]=="PASS" for v in tests.values()),"total":len(tests),
                  "assets_ok":assets_ok,"baseline_ok":baseline_ok,"changed_sources":changed}))
sys.exit(0 if summary["status"]=="PASS" else 1)
