"""Combine exact-source ModelSim units and an independently run RTL graph.

No expected values are changed. The graph must use the same byte-exact RTL
and testbench as the ModelSim run's initial snapshot; every log is archived.
"""
from pathlib import Path
from hashlib import sha256
from datetime import datetime, timezone
import argparse
import json
import shutil
import sys
import re

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tests/full_rtl"
sys.path.insert(0, str(Path(__file__).parent))
from compiled_sim import sources, tests


def digest(path):
    return sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--start", required=True, type=Path)
    graph_input = parser.add_mutually_exclusive_group(required=True)
    graph_input.add_argument("--native", type=Path)
    graph_input.add_argument("--modelsim-graph", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    initial = json.loads(args.start.read_text(encoding="utf-8-sig"))
    assert initial["rtl_sources"] == sources(), "Mixed RTL revisions"
    assert initial["test_sources"] == tests(), "ModelSim test inputs changed"
    native = json.loads(args.native.read_text(encoding="utf-8-sig")) if args.native else None
    assert not native, "Current full graph requires the actual Intel memory model in ModelSim"
    graph_log = args.native.parent / "graph.log" if native else args.modelsim_graph
    graph_text = graph_log.read_text(errors="replace")
    graph_markers = [x for x in graph_text.splitlines() if "LLM_GRAPH_PASS" in x]
    assert len(graph_markers) == 1, "Missing or ambiguous graph PASS marker"
    graph_marker = graph_markers[0]
    if native:
        assert native["status"] == "PASS" and native["rtl_sources"] == initial["rtl_sources"]
    if native and "cases" in native:
        graph_case = native["cases"]["graph"]
        assert native["test_sources"] == tests()
        assert graph_case["test_sha256"] == digest(HERE / "tb_graph.sv")
        assert digest(graph_log) == graph_case["log_sha256"]
        assert digest(args.native.parent / "graph_compile.log") == graph_case["compile_log_sha256"]
        assert graph_marker == native["tests"]["tb_llm_graph"]
        shutil.copyfile(args.native.parent / "graph_compile.log", args.output / "graph_compile.log")
    elif native:
        assert native["test_sha256"] == digest(HERE / "tb_graph.sv")
        assert graph_marker == native["marker"]
    assert "causal=checked" in graph_marker
    evidence = {"status": "PASS", "verified_utc": datetime.now(timezone.utc).isoformat(),
                "scope": "Six exact-source ModelSim units plus complete RTL graph with actual Intel memory IP",
                "rtl_sources": initial["rtl_sources"], "test_sources": initial["test_sources"],
                "tests": {}, "simulators": {}, "evidence": {},
                "runner_sources": {"tools/llm/merge_unit_evidence.py": digest(Path(__file__)),
                                   "tools/llm/compiled_sim.py": digest(Path(__file__).with_name("compiled_sim.py"))}}
    compile_log = HERE / "build/compile.log"
    compile_text = compile_log.read_text(errors="replace")
    assert re.search(r"Errors: 0, Warnings: \d+", compile_text), "ModelSim compile failed"
    compile_warnings = [line for line in compile_text.splitlines() if "** Warning" in line]
    assert all("(vlog-2583) [SVCHK]" in line and
               "Extra checking for conflicts with always_comb and always_latch variables is done at vopt time" in line
               for line in compile_warnings), "Unreviewed ModelSim compile warning"
    evidence["compile_warnings"] = compile_warnings
    # ModelSim prints local log start/end dates. Require each run after this
    # compile, rather than accepting a stale marker from another revision.
    assert compile_log.stat().st_mtime >= args.start.stat().st_mtime, "Start snapshot is newer than compile"
    if not native:
        assert graph_log.stat().st_mtime >= compile_log.stat().st_mtime, "Stale ModelSim graph log"
        assert re.search(r"Errors: 0, Warnings: 0", graph_text), "Graph simulation did not finish cleanly"
        assert not re.search(r"# \*\* (Fatal|Error|Warning)", graph_text)
    shutil.copyfile(compile_log, args.output / "compile.log")
    assert "altera_mf_ver.altsyncram" in graph_text, "Graph did not load the actual Intel RAM model"
    for case in ("memory", "math", "ram", "protocol", "selection", "operators"):
        top = "tb_quartus_memory" if case == "memory" else f"tb_llm_{case}"
        log = HERE / f"build/{top}.log"
        content = log.read_text(errors="replace")
        assert log.stat().st_mtime >= compile_log.stat().st_mtime, f"Stale log: {top}"
        assert re.search(r"Errors: 0, Warnings: \d+", content) and not re.search(r"# \*\* (Fatal|Error)", content)
        warnings = [line for line in content.splitlines() if line.startswith("# ** Warning")]
        assert not warnings or (case == "ram" and len(warnings) == 2 and
            "(vsim-2685) [TFMPC]" in warnings[0] and
            "(vsim-3722)" in warnings[1] and "Missing connection for port 'wr_busy'" in warnings[1]), \
            f"Unreviewed simulation warning: {case}"
        markers = [line for line in content.splitlines() if "_PASS" in line]
        assert len(markers) == 1, f"Invalid PASS marker: {top}"
        if case in {"memory", "protocol", "selection"}:
            assert "altera_mf_ver.altsyncram" in content, f"Actual Intel RAM model missing: {case}"
        shutil.copyfile(log, args.output / log.name)
        evidence["tests"][top] = markers[0]
        evidence["simulators"][top] = "ModelSim Intel FPGA Starter20.1"
        evidence["evidence"][top] = {"log": (args.output / log.name).relative_to(ROOT).as_posix(),
                                     "sha256": digest(log), "warnings": warnings}
    shutil.copyfile(graph_log, args.output / "graph.log")
    if native:
        shutil.copyfile(args.native, args.output / "native_graph.json")
    shutil.copyfile(args.start, args.output / "modelsim_start.json")
    evidence["tests"]["tb_llm_graph"] = graph_marker
    evidence["simulators"]["tb_llm_graph"] = native["simulator"] if native else "ModelSim Intel FPGA Starter20.1"
    evidence["evidence"]["tb_llm_graph"] = {"log": (args.output / "graph.log").relative_to(ROOT).as_posix(), "sha256": digest(graph_log)}
    assert sources() == initial["rtl_sources"] and tests() == initial["test_sources"]
    result = json.dumps(evidence, indent=2) + "\n"
    (args.output / "unit_results.json").write_text(result)
    (HERE / "unit_results.json").write_text(result)
    print("MERGED_SEVEN_UNIT_PASS: identical RTL/test hashes; six ModelSim units plus actual-IP full graph")


if __name__ == "__main__":
    main()
