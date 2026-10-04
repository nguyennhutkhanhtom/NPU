"""Compile and verify the RAM model shipped with the recorded Quartus install.

This utility compiles simulation support only; it does not run an application
or reference inference. Application entry points still check the hardware gate.
Vendor source and compiled libraries remain in ignored local build directories.
"""
from pathlib import Path
from hashlib import sha256
import argparse
import json
import re
import subprocess


def digest(path):
    return sha256(Path(path).read_bytes()).hexdigest()


def model_source(timing_path):
    timing_path = Path(timing_path)
    timing = json.loads(timing_path.read_text(encoding="utf-8-sig"))
    commands_path = timing_path.parent / "commands.json"
    assert digest(commands_path) == timing["commands_sha256"], "Timing commands changed"
    commands = json.loads(commands_path.read_text(encoding="utf-8-sig"))
    executable = Path(next(item["executable"] for item in commands if item["stage"] == "map"))
    source = executable.parent.parent / "eda/sim_lib/altera_mf.v"
    assert source.is_file(), "Recorded Quartus installation has no RAM simulation model"
    return source.resolve(), timing["quartus_version"]


def object_hashes(library):
    return {p.relative_to(library).as_posix(): digest(p) for p in sorted(library.rglob("*"))
            if p.is_file() and (p.name in ("_info", "_vmake") or p.suffix in (".qdb", ".qpg", ".qtl"))}


def verify_model(manifest_path, timing_path):
    manifest_path = Path(manifest_path).resolve()
    model = json.loads(manifest_path.read_text())
    source, version = model_source(timing_path)
    assert model["quartus_version"] == version and Path(model["source"]) == source
    assert digest(source) == model["source_sha256"], "Installed RAM model changed"
    library = Path(model["library"])
    assert library.name == "altera_mf_ver" and library.is_dir()
    assert object_hashes(library) == model["objects_sha256"], "Compiled RAM model changed"
    for executable, expected in model["compiler_sha256"].items():
        assert digest(executable) == expected, "RAM-model compiler changed"
    compile_path = manifest_path.parent / "compile.log"
    assert digest(compile_path) == model["compile_sha256"]
    text = compile_path.read_text(errors="replace")
    assert "Errors: 0, Warnings: 0" in text and not re.search(r"\*\* (Error|Warning)", text)
    return model


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timing", type=Path, required=True)
    parser.add_argument("--sim-bin", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    manifest_path = output / "manifest.json"
    if output.exists():
        verify_model(manifest_path, args.timing)
        print("QUARTUS_RAM_MODEL_VERIFIED: " + str(manifest_path))
        return
    source, version = model_source(args.timing)
    executables = {name: (args.sim_bin / (name + ".exe")).resolve() for name in ("vlib", "vlog")}
    compiler_hashes = {str(p): digest(p) for p in executables.values()}
    output.mkdir(parents=True)
    library = output / "altera_mf_ver"
    commands = [[str(executables["vlib"]), str(library)],
                [str(executables["vlog"]), "-work", str(library), str(source), "-l", str(output / "compile.log")]]
    for name, command in zip(("vlib", "vlog"), commands):
        with (output / (name + ".console")).open("wb") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
    model = {"scope": "Actual RAM simulation model only; no application execution",
             "quartus_version": version, "source": str(source), "source_sha256": digest(source),
             "library": str(library), "compiler_sha256": compiler_hashes, "commands": commands,
             "compile_sha256": digest(output / "compile.log"), "objects_sha256": object_hashes(library)}
    manifest_path.write_text(json.dumps(model, indent=2) + "\n")
    verify_model(manifest_path, args.timing)
    print("QUARTUS_RAM_MODEL_PREPARED: " + str(manifest_path))


if __name__ == "__main__":
    main()
