"""Run the unchanged RTL/testbench through native Verilator; gate applications.

Builds live in TEMP because GNU Make rejects spaces in the workspace path.
No RTL macros, expected-value edits, or CPU graph substitution are introduced.
"""
from pathlib import Path
from hashlib import sha256
from datetime import datetime, timezone
from collections import Counter
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tests/full_rtl"
RTL = ROOT / "Verilog Source code"
CASES = {"math": "LLM_MATH_PASS", "ram": "LLM_RAM_PASS", "protocol": "LLM_PROTOCOL_PASS",
         "selection": "SELECT_EDGE_PASS", "operators": "LLM_OPERATORS_PASS", "graph": "LLM_GRAPH_PASS"}
MODULES = ("npu_pkg.sv", "llm_pkg.sv", "llm_soc.sv", "llm_math.sv", "llm_bank_ram.sv",
           "llm_parameter_ram.sv", "pipelined_word_ram.sv", "quartus_word_ram.sv", "banked_word_ram.sv",
           "sram_256_wrapper.sv", "norm.sv", "div.sv", "sigmoid.sv")


def digest(path):
    return sha256(path.read_bytes()).hexdigest()


def sources():
    return {p.name: digest(p) for p in sorted(RTL.iterdir()) if p.suffix in {".sv", ".v", ".svh", ".mem"}}


def tests():
    return {p.name: digest(p) for p in sorted(HERE.iterdir())
            if (p.name.startswith("tb_") and p.suffix == ".sv") or p.name == "run_units.ps1"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--case", choices=[*CASES, "all", "application"], default="all")
    parser.add_argument("--timing", type=Path)
    parser.add_argument("--publish-units", action="store_true")
    parser.add_argument("--prompt", default="Once upon a time, Lily found a tiny kitten.")
    parser.add_argument("--new-tokens", type=int, default=96)
    parser.add_argument("--temperature", type=int, default=166)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--min-new", type=int, default=64)
    parser.add_argument("--tool-root", type=Path, default=Path(tempfile.gettempdir()) / "npu_verilator_5050/mingw64")
    parser.add_argument("--mingw-bin", type=Path, default=Path("C:/msys64/mingw64/bin"))
    parser.add_argument("--msys-bin", type=Path, default=Path("C:/msys64/usr/bin"))
    args = parser.parse_args()
    if args.case in {"all", "protocol", "selection", "graph", "application"}:
        parser.error("Current FPGA tests require the actual Intel altsyncram model. "
                     "Use tests/full_rtl/run_units.ps1 or run_application.ps1 with altera_mf_ver; "
                     "native simulation does not substitute a different memory configuration.")
    if args.publish_units and args.case != "all":
        parser.error("Only the complete six-group run can publish unit_results.json")
    if args.case == "application":
        if not args.timing:
            parser.error("Application requires --timing with exact-source passing hardware evidence")
        sys.path.insert(0, str(HERE))
        from check_gate import check_gate
        check_gate(args.timing)
        subprocess.run([sys.executable, str(HERE / "export_checkpoint.py"), "--timing", str(args.timing),
                        "--prompt", args.prompt, "--new-tokens", str(args.new_tokens),
                        "--temperature", str(args.temperature), "--seed", str(args.seed),
                        "--min-new", str(args.min_new)], cwd=ROOT, check=True)
    executable = args.tool_root / "bin/verilator_bin.exe"
    if not executable.is_file():
        parser.error(f"Missing local Verilator runtime: {executable}")
    environment = os.environ.copy()
    environment["VERILATOR_ROOT"] = (args.tool_root / "share/verilator").as_posix()
    environment["PATH"] = os.pathsep.join(map(str, (args.tool_root / "bin", args.mingw_bin, args.msys_bin))) + os.pathsep + environment["PATH"]
    version = subprocess.check_output([str(executable), "--version"], env=environment, text=True).strip()
    compiler = subprocess.check_output([str(args.mingw_bin / "g++.exe"), "--version"], env=environment, text=True).splitlines()[0]
    before, test_before = sources(), tests()
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    workspace = Path(tempfile.gettempdir()) / "npu_compiled" / run_id
    if " " in str(workspace):
        parser.error("TEMP path contains spaces; use a TEMP directory without spaces for GNU Make")
    evidence = HERE / "build/compiled" / run_id
    evidence.mkdir(parents=True)
    workspace.mkdir(parents=True)
    shutil.copytree(RTL, workspace / "rtl")
    assert {p.name: digest(p) for p in (workspace / "rtl").iterdir() if p.name in before} == before
    cases = list(CASES) if args.case == "all" else [args.case]
    record = {"status": "RUNNING", "simulator": version, "compiler": compiler,
              "verified_utc": None, "rtl_sources": before, "test_sources": test_before,
              "runner_sources": {"tools/llm/compiled_sim.py": digest(Path(__file__))},
              "scope": "Unchanged RTL and testbench, native compiled simulation", "tests": {}, "cases": {}}
    record_path = evidence / "result.json"
    try:
        for case in cases:
            application = case == "application"
            tb = HERE / ("application_tb.sv" if application else f"tb_{case}.sv")
            top = "tb_full_rtl_application" if application else f"tb_llm_{case}"
            shutil.copyfile(tb, workspace / tb.name)
            assert digest(workspace / tb.name) == digest(tb)
            command = [str(executable), "--binary", "--timing", "--assert", "-Wno-fatal",
                       "--top-module", top, "--Mdir", f"obj_{case}", "-j", "4", "-Irtl"]
            if application:
                shutil.copyfile(HERE / "build/config.svh", workspace / "config.svh")
                command.append("-I.")
            command.extend(f"rtl/{name}" for name in MODULES)
            command.append(tb.name)
            compile_log = evidence / f"{case}_compile.log"
            with compile_log.open("w") as output:
                subprocess.run(command, cwd=workspace, env=environment, stdout=output,
                               stderr=subprocess.STDOUT, check=True)
            warnings = Counter(re.findall(r"%Warning-([A-Z0-9_]+):", compile_log.read_text(errors="replace")))
            program = workspace / f"obj_{case}/V{top}.exe"
            log = evidence / f"{case}.log"
            started = time.monotonic()
            with log.open("w") as output:
                subprocess.run([str(program)], cwd=ROOT, env=environment, stdout=output,
                               stderr=subprocess.STDOUT, check=True)
            marker = "FULL_RTL_APPLICATION_PASS" if application else CASES[case]
            matches = [line for line in log.read_text(errors="replace").splitlines() if marker in line]
            assert len(matches) == 1, f"Missing or ambiguous success marker: {case}"
            record["tests"][top] = matches[0]
            record["cases"][case] = {"command": command, "test_sha256": digest(tb),
                                     "binary_sha256": digest(program), "log_sha256": digest(log),
                                     "compile_log_sha256": digest(compile_log), "warnings": dict(warnings),
                                     "elapsed_seconds": round(time.monotonic() - started, 3)}
            print(matches[0], flush=True)
        assert sources() == before and tests() == test_before, "RTL/test inputs changed during compiled simulation"
        assert digest(Path(__file__)) == record["runner_sources"]["tools/llm/compiled_sim.py"]
        record.update(status="PASS", verified_utc=datetime.now(timezone.utc).isoformat())
        if args.case == "application":
            check_gate(args.timing)
            # The finalizer consumes the canonical application log. Preserve
            # this run's log before publishing; never accept an earlier marker.
            shutil.copyfile(evidence / "application.log", HERE / "build/application.log")
            subprocess.run([sys.executable, str(HERE / "finalize_application.py"),
                            "--timing", str(args.timing)], cwd=ROOT, check=True)
        if args.publish_units:
            (HERE / "unit_results.json").write_text(json.dumps(record, indent=2) + "\n")
    except Exception as error:
        record.update(status="FAIL", failure=str(error), verified_utc=datetime.now(timezone.utc).isoformat())
        raise
    finally:
        record_path.write_text(json.dumps(record, indent=2) + "\n")
        print(f"COMPILED_EVIDENCE: {record_path}", flush=True)


if __name__ == "__main__":
    main()
