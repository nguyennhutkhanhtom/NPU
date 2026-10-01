"""Record a completed model run and render the supplied MNIST samples."""
from datetime import datetime, timedelta, timezone
from hashlib import sha256
from importlib.metadata import distributions
from pathlib import Path
import json
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent


def digest(path):
    return sha256(path.read_bytes()).hexdigest()


def main():
    cpu = json.loads((ROOT / "cpu_reference.json").read_text())
    upstream = json.loads((ROOT / "upstream_manifest.json").read_text(encoding="utf-8-sig"))
    history = json.loads((ROOT / "checkpoint_history.json").read_text(encoding="utf-8-sig"))
    log = (ROOT / "model_demo.log").read_text()
    compile_log = (ROOT / "compile.log").read_text()
    assert "Errors: 0, Warnings: 0" in compile_log
    assert "# Errors: 0, Warnings: 0" in log
    assert re.search(r"^# \*\* (Fatal|Error)", log, re.M) is None
    marker = re.search(r"MODEL_DEMO_PASS commands=(\d+) host_checks=(\d+) samples_and_repeats=(\d+) runs=(\d+)", log)
    assert marker
    runs = [{"sample": int(sample), "layer": int(layer), "active_cycles": int(cycles)}
            for sample, layer, cycles in re.findall(r"MODEL_RUN_DONE sample=(\d+) layer=(\d+) active_cycles=(\d+)", log)]
    predictions = [{"sample": int(sample), "label": int(label), "cpu_prediction": int(cpu_pred), "rtl_prediction": int(rtl_pred)}
                   for sample, label, cpu_pred, rtl_pred in re.findall(r"MODEL_SAMPLE_PASS sample=(\d+) label=(\d+) cpu_prediction=(\d+) rtl_prediction=(\d+)", log)]
    assert len(runs) == 42 and len(predictions) == 12
    assert all(item["rtl_prediction"] == item["cpu_prediction"] for item in predictions)
    staged = [item for item in predictions if item["sample"] < 10]
    assert len(staged) == 10
    assert sum(item["label"] == item["rtl_prediction"] for item in staged) == 10
    words = [int(line, 16) for line in (ROOT / "parameter.mem").read_text().splitlines()]
    assert len(words) == 1024
    (ROOT / "parameter.bin").write_bytes(b"".join(word.to_bytes(32, "little") for word in words))
    commands = [[int(value, 16) for value in line.split()] for line in (ROOT / "host_vectors.txt").read_text().splitlines()]
    program = {}
    matrix_words = {}
    ws_descriptors = {}
    for op, address, data, mask in commands:
        if op == 1:
            if 0x30000 <= address < 0x30800:
                program[(address - 0x30000) // 4] = data
            if 0x20100 <= address < 0x20180:
                matrix_words[address] = data
            if 0x20000 <= address < 0x20080:
                ws_descriptors[address] = data
    assert len(program) == 12 and program[11] == 0x1e00
    program_words = [program[pc] for pc in range(12)]
    (ROOT / "program.mem").write_text("".join(f"{word:04x}\n" for word in program_words), encoding="utf-8", newline="\n")
    program_map = {"instruction_count_including_halt": 12, "engine_operations": 11,
                   "words": program_words, "host_instruction_bytes": 48, "physical_instruction_bits": 156,
                   "workspace_descriptors": {f"{address:08x}": value for address, value in ws_descriptors.items()},
                   "matrix_descriptor_words": {f"{address:08x}": value for address, value in matrix_words.items()},
                   "buffer_layout": [{"name": name, "base_word": base, "reserved_words": count, "reserved_bytes": count*32}
                                     for name, base, count in [("input_s16",0,16),("hidden_a_s16",32,10),
                                     ("hidden_b_s16",64,10),("logits_s32",80,2),("q_s8",96,8),("z_s32",128,32)]],
                   "workspace_reserved_payload_bytes": 2496, "workspace_high_water_bytes": 5120,
                   "parameter_weight_bytes": 31360, "parameter_image_bytes": 32768}
    (ROOT / "program_layout.json").write_text(json.dumps(program_map, indent=2) + "\n", encoding="utf-8", newline="\n")

    font_path = Path("C:/Windows/Fonts/segoeui.ttf")
    title_font = ImageFont.truetype(str(font_path), 24)
    font = ImageFont.truetype(str(font_path), 19)
    canvas = Image.new("RGB", (1100, 500), "#f1f4f8")
    draw = ImageDraw.Draw(canvas)
    draw.text((20, 12), "BitNetMCU: supplied 16 x 16 S8 samples", fill="#172b45", font=title_font)
    for index, sample in enumerate(cpu["samples"]):
        x = 12 + (index % 5) * 220
        y = 58 + (index // 5) * 220
        draw.rounded_rectangle((x, y, x+208, y+207), radius=9, fill="white")
        pixels = np.array(sample["input"], dtype=np.int16).reshape(16,16)
        image_values = np.rint((pixels-pixels.min()) * 255.0 / (pixels.max()-pixels.min())).astype(np.uint8)
        image = Image.fromarray(image_values).resize((128,128), Image.Resampling.NEAREST)
        canvas.paste(image, (x+40,y+9))
        prediction = staged[index]
        draw.text((x+10,y+142), f"#{index} Label: {sample['label']}", fill="#172b45", font=font)
        draw.text((x+10,y+169), f"CPU: {prediction['cpu_prediction']}   RTL: {prediction['rtl_prediction']}", fill="#17613a", font=font)
    canvas.save(ROOT / "samples_predictions.png")

    end_match = re.search(r"End time: (\d\d:\d\d:\d\d) on (\w+ \d\d,\d{4})", log)
    ended = datetime.strptime(" ".join(end_match.groups()), "%H:%M:%S %b %d,%Y").replace(tzinfo=timezone(timedelta(hours=7)))
    rtl_hashes = {path.name: digest(path) for path in sorted((REPO / "Verilog Source code").iterdir())
                  if path.suffix in [".sv", ".v", ".svh", ".mem"]}
    assets = [path for path in ROOT.iterdir() if path.suffix in [".mem", ".bin", ".sv", ".py", ".ps1", ".png"]]
    assets += [ROOT/name for name in ["host_vectors.txt","cpu_reference.json","program_layout.json","compile.log","model_demo.log"]]
    result = {"status": "PASS", "verified_utc": ended.astimezone(timezone.utc).isoformat(),
              "compile_errors":0,"compile_warnings":0,"simulation_errors":0,"simulation_warnings":0,
              "rtl_sources":rtl_hashes,"demo_assets":{path.name:digest(path) for path in sorted(assets)},
              "upstream":upstream,"checkpoint_history":history,"checkpoint_sha256":cpu["checkpoint_sha256"],
              "checkpoint_graph_source_url":f"https://github.com/cpldcpu/BitNetMCU/blob/{history['checkpoint_commit']}/BitNetMCU.py",
              "historical_source_hashes":{path.name:digest(path) for path in sorted((ROOT/"upstream").glob("historical_*"))},
              "tools":{"python":sys.version,"numpy":np.__version__,"simulator_compile_header":compile_log.splitlines()[0],
                       "scoped_python_packages":{item.metadata['Name']:item.version for item in distributions(path=[str(ROOT/'packages')])}},
              "commands":int(marker.group(1)),"host_checks":int(marker.group(2)),"sample_checks_including_repeats":int(marker.group(3)),
              "runs":runs,"predictions":predictions,"unique_samples":10,"original_cpu_correct":10,"export_integer_correct":10,"rtl_correct":10,
              "intermediate_layers_checked":40,"whole_graph_runs":2,"whole_graph_active_cycles":[item['active_cycles'] for item in runs if item['layer']>=4],
              "program_layout":program_map,"weight_load_host_writes":sum(op==1 and address<0x8000 for op,address,_,_ in commands),
              "input_load_host_writes":sum(op==1 and 0x10000<=address<0x12000 for op,address,_,_ in commands),
              "loading_note":"Loading write counts are separate from active program cycles; staged observational host reads are excluded from active cycles.",
              "accuracy_scope":"Ten supplied labelled MNIST examples only; no full dataset accuracy claim.",
              "semantic_notes":["Binary codes are canonical CPU float32 sign(w-mean(w)); one fc3 weight maps to zero.",
                                "Learned meanabs weight magnitude is preserved in fixed-point factors and runtime composition.",
                                "Original CPU graph outputs are float32; RTL is bit-exact to independent exported integer reference.",
                                "2496 bytes is reserved buffer payload, not a measured dynamic liveness peak.",
                                "Simulation clock and cycle counts are not ASIC timing or PPA measurements."]}
    (ROOT / "results.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("MODEL_RESULTS_PASS", {key:result[key] for key in ["commands","host_checks","unique_samples","rtl_correct","whole_graph_active_cycles"]})


if __name__ == "__main__":
    main()
