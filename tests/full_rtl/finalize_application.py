from pathlib import Path
import argparse
import json
import sys
import re
from datetime import datetime, timezone
from hashlib import sha256
from check_gate import check_gate

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--timing", required=True, type=Path)
    args = parser.parse_args()
    gate = check_gate(args.timing)
    sys.path.insert(0, str(ROOT/"tests/language_demo/packages"))
    from tokenizers import Tokenizer
    reference = json.loads((HERE/"build/reference.json").read_text())
    assert reference["rtl_sources"] == gate["rtl_sources"], "Application was prepared for different RTL"
    assert reference["timing_manifest_sha256"] == sha256(args.timing.read_bytes()).hexdigest()
    for name, digest in reference["runner_sources"].items():
        assert sha256((HERE/name).read_bytes()).hexdigest() == digest, f"Application source changed: {name}"
    for name, digest in reference["input_files"].items():
        assert sha256((HERE/"build"/name).read_bytes()).hexdigest() == digest, f"Application input changed: {name}"
    compile_path, log_path = HERE/"build/application_compile.log", HERE/"build/application.log"
    assert compile_path.stat().st_mtime >= (HERE/"build/reference.json").stat().st_mtime, "Stale application compile"
    assert log_path.stat().st_mtime >= compile_path.stat().st_mtime, "Stale application simulation"
    compile_text, log_text = compile_path.read_text(), log_path.read_text()
    assert re.search(r"Errors: 0, Warnings: \d+", compile_text), "Application compile failed"
    compile_warnings = [line for line in compile_text.splitlines() if "** Warning" in line]
    assert all("(vlog-2583) [SVCHK]" in line and "Extra checking for conflicts with always_comb and always_latch variables is done at vopt time" in line
               for line in compile_warnings), "Unreviewed application compile warning"
    assert re.search(r"Errors: 0, Warnings: 0", log_text) and not re.search(r"# \*\* (Fatal|Error|Warning)", log_text), "Application simulation did not finish cleanly"
    assert "altera_mf_ver.altsyncram" in log_text, "Application did not load actual Intel RAM model"
    markers = [line for line in log_text.splitlines() if "FULL_RTL_APPLICATION_PASS" in line]
    assert len(markers) == 1, "Missing or ambiguous application PASS marker"
    tokens = [int(x) for x in (HERE/"build/rtl_tokens.txt").read_text().split()]
    assert tokens == reference["expected_ids"]
    tokenizer = Tokenizer.from_file(str(ROOT/"tests/language_demo/upstream/tokenizer.json"))
    text = tokenizer.decode(tokens)
    result = {"status":"PASS", "verification":"Exact RTL/reference continuation token matching",
              "text_quality":{"status":"NOT_ASSESSED", "note":"Token matching alone does not establish a meaningful coherent paragraph; inspect the actual RTL-decoded text separately."},
              "verified_utc":datetime.now(timezone.utc).isoformat(),
              "execution":"Entire prefill/decode graph and token selection on RTL; CPU host only loads data/tokenizes",
              "reference":reference,"rtl_token_ids":tokens,"rtl_text":text,
              "timing_manifest_sha256":sha256(args.timing.read_bytes()).hexdigest(),
              "rtl_sources":gate["rtl_sources"],
              "compile_warnings":compile_warnings,
              "evidence_sha256":{name:sha256((HERE/"build"/name).read_bytes()).hexdigest()
                                 for name in ("application_compile.log", "application.log", "reference.json", "rtl_tokens.txt")},
              "application_marker":markers[0]}
    (HERE/"application_results.json").write_text(json.dumps(result,indent=2)+"\n")
    (HERE/"generated_text.md").write_text(f"# RTL-generated continuation\n\nPrompt: {reference['prompt']}\n\n{text}\n")
    print("FULL_RTL_APPLICATION_EVIDENCE_PASS")


if __name__ == "__main__":
    main()
