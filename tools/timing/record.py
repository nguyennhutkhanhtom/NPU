"""Archive actual Quartus timing evidence and reject changed compilation inputs."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess

REPO = Path(__file__).resolve().parents[2]
RTL_SUFFIXES = {".sv", ".v", ".svh", ".mem"}
TEXT_SUFFIXES = {".rpt", ".summary", ".html", ".txt", ".log", ".console"}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def save_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8", newline="\n")


def display_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO).as_posix()
    except ValueError:
        return str(path.resolve())


def input_hashes(project: Path, rtl: Path) -> dict:
    sources = {
        p.relative_to(rtl).as_posix(): sha256(p.read_bytes())
        for p in sorted(rtl.rglob("*"))
        if p.is_file() and p.suffix.lower() in RTL_SUFFIXES
    }
    if not sources:
        raise ValueError(f"No RTL/source assets found in {rtl}")
    config = {}
    for suffix in (".qpf", ".qsf", ".sdc"):
        path = project.with_suffix(suffix)
        if not path.is_file():
            raise FileNotFoundError(f"Missing project input: {path}")
        # Quartus may rewrite project text as CRLF without changing settings.
        # Compare canonical LF configuration, while RTL remains byte-exact.
        config[path.name] = sha256(path.read_bytes().replace(b"\r\n", b"\n"))
    qsf = project.with_suffix(".qsf").read_text(encoding="utf-8-sig")
    assigned = re.findall(
        r"^set_global_assignment -name (?:SYSTEMVERILOG_FILE|VERILOG_FILE|VERILOG_INCLUDE_FILE)\s+"
        r'(?:"([^"]+)"|\{([^}]+)\}|(\S+))', qsf, re.MULTILINE,
    )
    for quoted, braced, plain in assigned:
        path = (project.parent / (quoted or braced or plain)).resolve()
        try:
            name = path.relative_to(rtl).as_posix()
        except ValueError as error:
            raise ValueError(f"Project source is outside the recorded RTL directory: {path}") from error
        if name not in sources:
            raise ValueError(f"Project source was not included in the RTL snapshot: {path}")
    if not assigned:
        raise ValueError("No source-file assignments found in the QSF")
    return {"rtl_sources": sources, "configuration": config}


def first_timing_path(text: str) -> dict | None:
    summary = text.split("; Summary of Paths", 1)
    if len(summary) != 2:
        return None
    for line in summary[1].splitlines():
        fields = [part.strip() for part in line.split(";")[1:-1]]
        if len(fields) == 8 and re.fullmatch(r"-?\d+(?:\.\d+)?", fields[0]):
            return {
                "slack_ns": float(fields[0]),
                "from": fields[1],
                "to": fields[2],
                "launch_clock": fields[3],
                "latch_clock": fields[4],
                "relationship_ns": float(fields[5]),
                "clock_skew_ns": float(fields[6]),
                "data_delay_ns": float(fields[7]),
            }
    return None


def stage_counts(text: str) -> dict:
    totals = re.findall(r"was successful\.\s+(\d+) errors?,\s+(\d+) warnings?\b", text)
    diagnostics = [
        {"kind": kind, "id": int(identifier), "message": message.strip()}
        for kind, identifier, message in re.findall(
            r"^(Critical Warning|Warning|Error) \((\d+)\): (.+)$", text, re.MULTILINE
        )
    ]
    return {
        "errors": int(totals[-1][0]) if totals else None,
        "warnings": int(totals[-1][1]) if totals else None,
        "reported_diagnostics": diagnostics,
    }


def report_metrics(output: Path, revision: str) -> dict:
    read = lambda name: (output / name).read_text(encoding="utf-8", errors="replace")
    summary = read(f"{revision}.sta.summary")
    corners = {}
    types = {"Setup": "setup", "Hold": "hold", "Recovery": "recovery", "Removal": "removal", "Minimum Pulse Width": "pulse"}
    pattern = re.compile(
        r"Type\s*:\s*(Slow|Fast) (\d+)mV (-?\d+)C Model "
        r"(Setup|Hold|Recovery|Removal|Minimum Pulse Width) '([^']+)'\s*"
        r"Slack\s*:\s*(-?\d+(?:\.\d+)?)\s*TNS\s*:\s*(-?\d+(?:\.\d+)?)"
    )
    for model, voltage, temperature, analysis, clock, slack, tns in pattern.findall(summary):
        name = f"{model.lower()}_{voltage}mv_{temperature}c"
        corner = corners.setdefault(name, {"clocks": {}})
        corner["clocks"].setdefault(clock, {})[types[analysis]] = {
            "slack_ns": float(slack), "tns_ns": float(tns)
        }
    expected = {f"{model}_1100mv_{temperature}c" for model in ("slow", "fast") for temperature in ("0", "85")}
    if set(corners) != expected:
        raise ValueError(f"Expected four actual timing corners, found {sorted(corners)}")
    for name, corner in corners.items():
        fmax_text = read(f"{name}_fmax.rpt")
        fmax_rows = re.findall(
            r"^;\s*([\d.]+) MHz\s*;\s*([\d.]+) MHz\s*;\s*([^;]+);", fmax_text, re.MULTILINE
        )
        if not fmax_rows:
            raise ValueError(f"No reported Fmax in {name}_fmax.rpt")
        corner["fmax"] = {
            clock.strip(): {"mhz": float(fmax), "restricted_mhz": float(restricted)}
            for fmax, restricted, clock in fmax_rows
        }
        corner["worst_setup_path"] = first_timing_path(read(f"{name}_setup.rpt"))
        corner["worst_hold_path"] = first_timing_path(read(f"{name}_hold.rpt"))
    unconstrained_text = read("extracted_unconstrained.rpt")
    unconstrained = {
        name.strip(): {"setup": int(setup), "hold": int(hold)}
        for name, setup, hold in re.findall(
            r"^;\s*(Illegal Clocks|Unconstrained Clocks|Unconstrained Input Ports|Unconstrained Input Port Paths|"
            r"Unconstrained Output Ports|Unconstrained Output Port Paths)\s*;\s*(\d+)\s*;\s*(\d+)\s*;",
            unconstrained_text, re.MULTILINE,
        )
    }
    if len(unconstrained) != 6:
        raise ValueError("Incomplete unconstrained-path summary")
    fit = read(f"{revision}.fit.summary")
    resources = {}
    for label, key in (
        ("Logic utilization (in ALMs)", "alms"), ("Total registers", "registers"),
        ("Total block memory bits", "block_memory_bits"), ("Total RAM Blocks", "ram_blocks"),
        ("Total DSP Blocks", "dsp_blocks"), ("Total pins", "pins"),
    ):
        match = re.search(rf"^{re.escape(label)}\s*:\s*([\d,]+)", fit, re.MULTILINE)
        if not match:
            raise ValueError(f"Missing fitted resource {label}")
        resources[key] = int(match[1].replace(",", ""))
    setup_slacks = [clock["setup"]["slack_ns"] for corner in corners.values() for clock in corner["clocks"].values() if "setup" in clock]
    stages = {stage: stage_counts(read(f"{revision}.{stage}.rpt")) for stage in ("map", "fit", "sta")}
    return {
        "corners": corners,
        "worst_fmax_mhz": min(row["mhz"] for corner in corners.values() for row in corner["fmax"].values()),
        "worst_restricted_fmax_mhz": min(row["restricted_mhz"] for corner in corners.values() for row in corner["fmax"].values()),
        "worst_setup_slack_ns": min(setup_slacks),
        "unconstrained": unconstrained,
        "fitted_resources": resources,
        "stage_counts": stages,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=REPO / "quartus/matmul_free")
    parser.add_argument("--rtl-dir", type=Path, default=REPO / "Verilog Source code")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-snapshot", type=Path)
    parser.add_argument("--snapshot-only", action="store_true")
    args = parser.parse_args()
    project = args.project.resolve()
    if project.suffix.lower() in (".qpf", ".qsf"):
        project = project.with_suffix("")
    rtl = args.rtl_dir.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    inputs = input_hashes(project, rtl)
    snapshot_path = args.source_snapshot or output / "sources_before.json"
    if args.snapshot_only:
        save_json(snapshot_path, {"captured_at_utc": datetime.now(timezone.utc).isoformat(), **inputs})
        print(f"TIMING_INPUT_SNAPSHOT_PASS: {len(inputs['rtl_sources'])} source assets")
        return
    snapshot = json.loads(snapshot_path.read_text(encoding="utf-8-sig"))
    if snapshot.get("rtl_sources") != inputs["rtl_sources"]:
        raise ValueError("RTL changed since the compilation snapshot; rerun with immutable sources")
    if "configuration" in snapshot and snapshot["configuration"] != inputs["configuration"]:
        raise ValueError("QPF/QSF/SDC changed since the compilation snapshot")
    archive = {}
    # Include manual snapshots from ignored build folders in the published
    # evidence. Runner snapshots already reside here; hash those as well.
    snapshot_raw = snapshot_path.read_bytes()
    snapshot_target = output / "sources_before.json"
    snapshot_target.write_bytes(snapshot_raw.replace(b"\r\n", b"\n"))
    archive[snapshot_target.name] = {
        "source": display_path(snapshot_path), "source_sha256": sha256(snapshot_raw),
        "archive_sha256": sha256(snapshot_target.read_bytes()),
        "source_bytes": len(snapshot_raw), "archive_bytes": snapshot_target.stat().st_size,
    }
    revision = project.name
    for stage in ("map", "fit", "sta"):
        for suffix in ("rpt", "summary"):
            source = project.parent / "output_files" / f"{revision}.{stage}.{suffix}"
            raw = source.read_bytes()
            normalized = raw.replace(b"\r\n", b"\n")
            target = output / source.name
            target.write_bytes(normalized)
            archive[target.name] = {
                "source": display_path(source), "source_sha256": sha256(raw),
                "archive_sha256": sha256(normalized), "source_bytes": len(raw),
                "archive_bytes": len(normalized),
                "source_modified_local": datetime.fromtimestamp(source.stat().st_mtime).astimezone().isoformat(),
            }
    # Keep the exact project constraints with each evidence set, without a stale
    # flow report from another compilation or a reconstructed timing summary.
    for suffix in (".qpf", ".qsf", ".sdc"):
        source = project.with_suffix(suffix)
        raw = source.read_bytes()
        target = output / source.name
        target.write_bytes(raw.replace(b"\r\n", b"\n"))
        archive[target.name] = {"source": display_path(source), "source_sha256": sha256(raw), "archive_sha256": sha256(target.read_bytes())}
    normalized_files = {}
    for path in sorted(output.rglob("*")):
        if path.is_file() and path.suffix.lower() in TEXT_SUFFIXES:
            raw = path.read_bytes()
            normalized = raw.replace(b"\r\n", b"\n")
            path.write_bytes(normalized)
            normalized_files[path.relative_to(output).as_posix()] = {
                "raw_sha256": sha256(raw), "archive_sha256": sha256(normalized),
                "archive_bytes": len(normalized),
            }
    metrics = report_metrics(output, revision)
    timing_pass = (
        metrics["worst_restricted_fmax_mhz"] >= 100
        and len(metrics["corners"]) == 4
        and all(set(corner["clocks"]) == {"clk"}
                and all(corner["clocks"]["clk"].get(kind, {}).get("slack_ns", -1) >= 0
                        and corner["clocks"]["clk"].get(kind, {}).get("tns_ns", -1) == 0
                        for kind in ("setup", "hold", "recovery", "removal", "pulse"))
                for corner in metrics["corners"].values())
        and all(value["setup"] == 0 and value["hold"] == 0 for value in metrics["unconstrained"].values())
        and all(stage["errors"] == 0 and not any(d["id"] == 332148 for d in stage["reported_diagnostics"])
                for stage in metrics["stage_counts"].values())
    )
    match = re.search(r"^Quartus Prime Version\s*:\s*(.+)$", (output / f"{revision}.fit.summary").read_text(), re.MULTILINE)
    settings = {}
    qsf = project.with_suffix(".qsf").read_text(encoding="utf-8-sig")
    for name in ("FAMILY", "DEVICE", "TOP_LEVEL_ENTITY", "SEED", "OPTIMIZATION_TECHNIQUE", "FITTER_EFFORT", "SDC_FILE"):
        values = re.findall(rf"^set_global_assignment -name {name}\s+(.+)$", qsf, re.MULTILINE)
        settings[name] = values[-1].strip() if values else None
    try:
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip()
    except (FileNotFoundError, subprocess.CalledProcessError):
        head = None
    save_json(output / "manifest.json", {
        "recorded_at_utc": datetime.now(timezone.utc).isoformat(), "git_head": head,
        "project": display_path(project), "rtl_dir": display_path(rtl),
        "quartus_version": match[1].strip() if match else None,
        "source_snapshot": display_path(snapshot_path), "source_hashes_verified": True,
        "source_snapshot_archive": snapshot_target.name,
        "configuration_hashes_verified": "configuration" in snapshot,
        "configuration_hash_normalization": "CRLF -> LF before comparison",
        **inputs, "settings": settings, "archives": archive,
        "commands_sha256": sha256((output / "commands.json").read_bytes()) if (output / "commands.json").is_file() else None,
        "normalization": "CRLF -> LF only", "text_reports": normalized_files,
        "metrics": metrics,
        "timing_100mhz_status": "PASS" if timing_pass else "FAIL",
        "scope": "Post-fit FPGA timing for the recorded device, constraints and inputs; not ASIC or board signoff",
    })
    print(f"TIMING_EVIDENCE_RECORDED: Fmax={metrics['worst_fmax_mhz']:.2f} MHz, setup={metrics['worst_setup_slack_ns']:.3f} ns")
    print("TIMING_100MHZ_" + ("PASS" if timing_pass else "FAIL"))


if __name__ == "__main__":
    main()
