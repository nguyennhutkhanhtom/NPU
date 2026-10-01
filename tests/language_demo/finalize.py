"""Validate simulator evidence and record a lightweight publication report."""
from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent


def digest(path):
    return sha256(path.read_bytes()).hexdigest()


def main():
    cpu = json.loads((ROOT / "cpu_reference.json").read_text())
    compile_log = (ROOT / "compile.log").read_text()
    sim_log = (ROOT / "language_demo.log").read_text()
    assert "Errors: 0, Warnings: 0" in compile_log
    assert "# Errors: 0, Warnings: 0" in sim_log
    assert re.search(r"^# \*\* (Fatal|Error)", sim_log, re.M) is None
    marker = re.search(r"LANGUAGE_DEMO_PASS commands=(\d+) checks=(\d+) runs=(\d+)", sim_log)
    assert marker
    runs = [{"case": int(case), "layer": int(layer), "active_cycles": int(cycles)}
            for case, layer, cycles in re.findall(r"LANGUAGE_LINEAR_PASS case=(\d+) layer=(\d+) active_cycles=(\d+)", sim_log)]
    assert len(runs) == 168 == int(marker.group(3))
    assert [run["case"] for run in runs] == list(range(168))
    assert int(marker.group(1)) == cpu["export"]["commands"]
    assert int(marker.group(2)) == cpu["export"]["logical_s32_outputs"] + 2 * len(runs)
    errors = [item["quantization_error"] for item in cpu["cases"]]
    result = {"status": "PASS", "verified_utc": datetime.now(timezone.utc).isoformat(),
              "model": cpu["model"], "upstream": cpu["upstream"], "parameters": cpu["parameters"],
              "tensor_count": cpu["tensor_count"], "backend": cpu["backend"], "sampling": cpu["sampling"],
              "runtime": cpu["runtime"],
              "generations": cpu["generations"], "export": cpu["export"], "layers": cpu["layers"],
              "compile_errors": 0, "compile_warnings": 0, "simulation_errors": 0, "simulation_warnings": 0,
              "commands": int(marker.group(1)), "host_checks": int(marker.group(2)), "runs": runs,
              "cycles_sum": sum(item["active_cycles"] for item in runs),
              "quantization_error": {"max_absolute": max(item["max_absolute"] for item in errors),
                                     "max_relative_l2": max(item["relative_l2"] for item in errors),
                                     "mean_relative_l2": sum(item["relative_l2"] for item in errors) / len(errors),
                                     "scope": "Linear outputs only; not full language quality or end-to-end integer generation"},
              "rtl_sources": {path.name: digest(path) for path in sorted((REPO / "Verilog Source code").iterdir())
                              if path.suffix in [".sv", ".v", ".svh", ".mem"]},
              "demo_assets": {path.name: digest(path) for path in sorted(ROOT.iterdir())
                              if path.is_file() and path.name in ["export_demo.py", "tb_language_demo.sv", "run.ps1", "setup.ps1",
                                                                 "fetch_assets.py", "finalize.py", "requirements.txt", "upstream_manifest.json",
                                                                 "host_vectors.txt", "cpu_reference.json", "compile.log", "language_demo.log"]},
              "limits": ["Full text generation ran on CPU, not on RTL.",
                         "RTL streamed 28 supported pretrained linear tensors; full model exceeds SRAM and needs additional operators.",
                         "No training, validation perplexity or full-dataset language evaluation was performed.",
                         "CPU timings exclude asset loading and are not ASIC latency/PPA.",
                         "RMS affine, RoPE, attention, FP16 embedding/head, residual and gating graph remain on CPU."]}
    (ROOT / "results.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("LANGUAGE_RESULTS_PASS", {key: result[key] for key in ["commands", "host_checks", "cycles_sum", "quantization_error"]})


if __name__ == "__main__":
    main()
