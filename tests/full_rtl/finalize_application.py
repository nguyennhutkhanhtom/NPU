from pathlib import Path
import argparse
import json
import sys
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
    tokens = [int(x) for x in (HERE/"build/rtl_tokens.txt").read_text().split()]
    assert tokens == reference["expected_ids"]
    tokenizer = Tokenizer.from_file(str(ROOT/"tests/language_demo/upstream/tokenizer.json"))
    text = tokenizer.decode(tokens)
    result = {"status":"PASS", "verified_utc":datetime.now(timezone.utc).isoformat(),
              "execution":"Entire prefill/decode graph and token selection on RTL; CPU host only loads data/tokenizes",
              "reference":reference,"rtl_token_ids":tokens,"rtl_text":text,
              "timing_manifest_sha256":sha256(args.timing.read_bytes()).hexdigest(),
              "rtl_sources":gate["rtl_sources"],
              "application_marker":next(x for x in (HERE/"build/application.log").read_text().splitlines() if "FULL_RTL_APPLICATION_PASS" in x)}
    (HERE/"application_results.json").write_text(json.dumps(result,indent=2)+"\n")
    (HERE/"generated_text.md").write_text(f"# RTL-generated continuation\n\nPrompt: {reference['prompt']}\n\n{text}\n")
    print("FULL_RTL_APPLICATION_EVIDENCE_PASS")


if __name__ == "__main__":
    main()
