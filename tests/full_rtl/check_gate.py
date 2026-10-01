"""Reject application execution unless the exact full graph closes at 100 MHz."""
from pathlib import Path
from hashlib import sha256
import argparse
import json

ROOT = Path(__file__).resolve().parents[2]
RTL = ROOT / "Verilog Source code"


def check_gate(manifest_path: Path) -> dict:
    evidence = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    assert evidence["source_hashes_verified"] and evidence["configuration_hashes_verified"]
    assert evidence["settings"]["TOP_LEVEL_ENTITY"] == "llm_soc", "Timing must cover the full graph top"
    actual = {p.name: sha256(p.read_bytes()).hexdigest() for p in RTL.iterdir()
              if p.suffix in {".sv", ".v", ".svh", ".mem"}}
    assert actual == evidence["rtl_sources"], "RTL changed after timing analysis"
    for name, digest in evidence["configuration"].items():
        path = ROOT / "quartus" / name
        assert sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() == digest, \
            f"Configuration changed after timing: {name}; final timing must use quartus/llm_soc"
    metrics = evidence["metrics"]
    assert metrics["worst_restricted_fmax_mhz"] >= 100, "Fmax is below 100 MHz"
    assert len(metrics["corners"]) == 4
    for corner, item in metrics["corners"].items():
        assert set(item["clocks"]) == {"clk"}
        for kind in ("setup", "hold", "recovery", "removal", "pulse"):
            result = item["clocks"]["clk"][kind]
            assert result["slack_ns"] >= 0 and result["tns_ns"] == 0, f"{corner} {kind} failed"
    for values in metrics["unconstrained"].values():
        assert values["setup"] == 0 and values["hold"] == 0, "Unconstrained paths exist"
    for stage in ("map", "fit", "sta"):
        assert metrics["stage_counts"][stage]["errors"] == 0
        for diagnostic in metrics["stage_counts"][stage]["reported_diagnostics"]:
            assert diagnostic["kind"] != "Error"
            assert diagnostic["id"] != 332148, "Timing requirements were not met"
    units = json.loads((Path(__file__).parent / "unit_results.json").read_text(encoding="utf-8-sig"))
    assert units["status"] == "PASS" and units["rtl_sources"] == actual, "Current operator units have not passed"
    assert set(units["tests"]) == {"tb_llm_math", "tb_llm_operators", "tb_llm_protocol", "tb_llm_ram", "tb_llm_graph", "tb_llm_selection"}, \
        "The selection boundary regression must pass along with all existing groups"
    tests = {p.name: sha256(p.read_bytes()).hexdigest() for p in Path(__file__).parent.iterdir()
             if p.name.startswith("tb_") and p.suffix == ".sv" or p.name == "run_units.ps1"}
    assert units["test_sources"] == tests, "Unit tests changed since the recorded run"
    return evidence


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    checked = check_gate(args.manifest)
    print(f"FULL_RTL_APPLICATION_GATE_PASS: Fmax={checked['metrics']['worst_restricted_fmax_mhz']} MHz")
