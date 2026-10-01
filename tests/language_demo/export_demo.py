"""Run the pinned pretrained graph and export real ternary linear observations.

CPU runs the full graph. RTL exercises the 28 supported linear tensors with
captured activations, streamed one tensor at a time. It does not run attention.
"""
from collections import OrderedDict
from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path
import json
import sys
import time

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
sys.path[:0] = [str(ROOT / "packages"), str(ROOT / "upstream")]
import numpy as np
import torch
from safetensors.torch import load_file
from tokenizers import Tokenizer
from nanofable.config import TIERS
from nanofable.model import build_model

PROMPTS = ["Once upon a time", "Lily had a little cat.", "In a small village, a boy"]
MAX_NEW_TOKENS = 32


def digest(path):
    return sha256(path.read_bytes()).hexdigest()


def rne(n, d):
    q, rem = divmod(abs(int(n)), int(d))
    q += 2 * rem > d or (2 * rem == d and q & 1)
    return -q if n < 0 else q


def coefficient(value):
    num, den = float(value).as_integer_ratio()
    for shift in range(47, -1, -1):
        magnitude = rne(num << shift, den)
        if 0 < magnitude < 1 << 24:
            return magnitude, shift
    raise ValueError("Cannot encode positive scale")


def packed(values, width):
    per_word = 256 // width
    mask = (1 << width) - 1
    return [sum((int(v) & mask) << (width * j) for j, v in enumerate(values[i:i + per_word]))
            for i in range(0, len(values), per_word)]


def main():
    torch.set_num_threads(1)
    cfg = json.loads((ROOT / "upstream" / "config.json").read_text())
    assert (cfg["n_layer"], cfg["n_embd"], cfg["n_head"], cfg["vocab"], cfg["ctx"]) == (4, 128, 4, 4096, 512)
    weights = load_file(str(ROOT / "upstream" / "model.safetensors"), device="cpu")
    # Published weights already contain scale * {-1,0,+1}; never requantize.
    model = build_model(TIERS["tiny"], "fp16")
    incompatible = model.load_state_dict(weights, strict=False)
    assert incompatible.missing_keys == ["lm_head.weight"] and not incompatible.unexpected_keys
    assert model.lm_head.weight.data_ptr() == model.tok_emb.weight.data_ptr()
    model.eval()
    tokenizer = Tokenizer.from_file(str(ROOT / "upstream" / "tokenizer.json"))
    assert tokenizer.get_vocab_size() == 4096
    assert [tokenizer.token_to_id(t) for t in ["<|bos|>", "<|eos|>", "<|pad|>"]] == [0, 1, 2]

    layers = OrderedDict()
    for name, module in model.named_modules():
        if isinstance(module, torch.nn.Linear) and name != "lm_head":
            array = module.weight.detach().numpy().copy()
            unique = np.unique(array)
            assert len(unique) == 3 and unique[0] == -unique[2] and unique[1] == 0
            scale = float(unique[2])
            codes = np.rint(array / scale).astype(np.int8)
            assert np.array_equal(array, codes.astype(np.float32) * scale)
            layers[name] = {"module": module, "codes": codes, "scale": scale, "observations": []}
    assert len(layers) == 28

    def capture_context(ids, context_name):
        handles = []
        def hook_for(name):
            def hook(module, args, output):
                layers[name]["observations"].append({"context": context_name,
                    "input": args[0][0, -1].detach().numpy().copy(),
                    "cpu_output": output[0, -1].detach().numpy().copy()})
            return hook
        for name, layer in layers.items():
            handles.append(layer["module"].register_forward_hook(hook_for(name)))
        with torch.no_grad():
            model(torch.tensor([ids], dtype=torch.long))
        for handle in handles:
            handle.remove()

    def generate(ids):
        output = []
        started = time.perf_counter()
        with torch.no_grad():
            for _ in range(MAX_NEW_TOKENS):
                logits, _ = model(torch.tensor([(ids + output)[-512:]], dtype=torch.long))
                token = int(logits[0, -1].argmax())
                if token == 1:
                    break
                output.append(token)
        return output, time.perf_counter() - started

    generations = []
    for prompt_id, prompt in enumerate(PROMPTS):
        ids = tokenizer.encode(prompt).ids
        capture_context(ids, f"prompt_{prompt_id}")
        tokens, duration = generate(ids)
        repeated, repeated_duration = generate(ids)
        assert tokens == repeated and tokens
        capture_context(ids + tokens, f"continuation_{prompt_id}")
        generations.append({"prompt": prompt, "prompt_token_ids": ids, "generated_token_ids": tokens,
                            "continuation": tokenizer.decode(tokens), "new_tokens": len(tokens),
                            "cpu_seconds": duration, "repeat_seconds": repeated_duration,
                            "deterministic_repeat_pass": True})

    commands = []
    def emit(op, a=0, b=0, c=0):
        commands.append(f"{op:x} {a:08x} {b & 0xffffffff:08x} {c & 0xffffffff:08x}")
    def write(address, value):
        emit(1, address, value)
    def memory(address, values, width, check=False):
        for index, word in enumerate(packed(values, width)):
            for lane in range(8):
                emit(2 if check else 1, address + index * 32 + lane * 4,
                     (word >> (32 * lane)) & 0xffffffff, 0xffffffff if check else 0)
    emit(0)
    layer_results = []
    all_cases = []
    weight_words_total = 0
    for layer_id, (name, layer) in enumerate(layers.items()):
        codes = layer["codes"]
        n, k = codes.shape
        row_words = (k + 127) // 128
        words = []
        for row in codes:
            words.extend(packed([3 if int(v) < 0 else int(v) for v in row], 2))
        assert len(words) == n * row_words <= 1024 and k <= 512
        weight_words_total += len(words)
        for index, word in enumerate(words):
            for lane in range(8):
                write(index * 32 + lane * 4, (word >> (lane * 32)) & 0xffffffff)
        path = ROOT / "images" / f"{layer_id:02d}_{name.replace('.', '_')}.mem"
        path.parent.mkdir(exist_ok=True)
        path.write_text("".join(f"{word:064x}\n" for word in words), encoding="utf-8", newline="\n")
        errors = []
        case_ids = []
        for observation in layer["observations"]:
            x = observation["input"]
            # Only the supported linear is exported. CPU supplies its input;
            # RMS affine, attention and gating remain in the full CPU graph.
            step = float(np.max(np.abs(x))) / 127.0
            assert step > 0
            q = np.rint(x.astype(np.float64) / step).astype(np.int8)
            assert np.max(np.abs(q.astype(np.int16))) <= 127
            m, shift = coefficient(step * layer["scale"] * (1 << 16))
            dot = codes.astype(np.int64) @ q.astype(np.int64)
            output = [rne(int(v) * m, 1 << shift) for v in dot]
            assert all(-(1 << 31) <= v < 1 << 31 for v in output)
            fixed_float = np.array(output, dtype=np.float64) / (1 << 16)
            original = observation["cpu_output"].astype(np.float64)
            delta = fixed_float - original
            absolute = float(np.max(np.abs(delta)))
            rms = float(np.sqrt(np.mean(delta * delta)))
            relative_l2 = float(np.linalg.norm(delta) / max(float(np.linalg.norm(original)), 1e-12))
            case_id = len(all_cases)
            emit(7, case_id, layer_id)
            write(0x20000, (k << 14))  # S8 input at workspace word 0.
            write(0x20010, (32 << 24) | (n << 14) | (3 << 12) | (16 << 7))
            descriptor = (k << 66) | (n << 56) | (m << 32) | (shift << 26) | (1 << 25) | 2
            for lane in range(3):
                write(0x20100 + lane * 4, (descriptor >> (lane * 32)) & 0xffffffff)
            memory(0x10000, q, 8)
            write(0x30000, (8 << 9) | (1 << 6))
            write(0x30004, 0x1e00)
            write(0x40000, 1)
            emit(3, 100000, 2, 15)
            memory(0x10400, output, 32, check=True)
            emit(2, 0x40004, 1, 0xffffffff)
            errors.append({"max_absolute": absolute, "rms": rms, "relative_l2": relative_l2})
            all_cases.append({"case": case_id, "layer": name, "context": observation["context"],
                              "input_step": step, "scale_m": m, "scale_r": shift,
                              "input_float": x.tolist(), "input_s8": q.astype(int).tolist(),
                              "cpu_output_float": original.tolist(), "reference_s32_f16": output,
                              "quantization_error": errors[-1]})
            case_ids.append(case_id)
        layer_results.append({"name": name, "k": k, "n": n, "weight_scale": layer["scale"],
                              "parameter_bytes": len(words) * 32, "cases": case_ids,
                              "input_quantization": "captured CPU linear input absmax / 127, nearest even S8",
                              "max_absolute_error": max(item["max_absolute"] for item in errors),
                              "max_relative_l2_error": max(item["relative_l2"] for item in errors)})
    (ROOT / "host_vectors.txt").write_text("\n".join(commands) + "\n", encoding="utf-8", newline="\n")
    upstream = json.loads((ROOT / "upstream_manifest.json").read_text())
    upstream["files"] = {str(path.relative_to(ROOT / "upstream")).replace("\\", "/"):
                         {"sha256": digest(path), "bytes": path.stat().st_size}
                         for path in sorted((ROOT / "upstream").rglob("*")) if path.is_file() and "__pycache__" not in str(path)}
    (ROOT / "upstream_manifest.json").write_text(json.dumps(upstream, indent=2) + "\n", encoding="utf-8", newline="\n")
    import safetensors
    import tokenizers
    result = {"cpu_status": "PASS", "cpu_verified_utc": datetime.now(timezone.utc).isoformat(),
              "model": "adrahmana/NanoFable-1M-ternary", "upstream": upstream,
              "backend": "PyTorch 2.5.1+cpu float32 graph, original dequantized FP16 checkpoint values",
              "sampling": "deterministic greedy argmax; max_new_tokens=32; EOS=1; no training",
              "runtime": {"python": sys.version, "torch": torch.__version__, "numpy": np.__version__,
                          "safetensors": safetensors.__version__, "tokenizers": tokenizers.__version__,
                          "torch_file": str(Path(torch.__file__).relative_to(REPO)).replace("\\", "/")},
              "parameters": sum(v.numel() for v in model.parameters()), "tensor_count": len(weights),
              "generations": generations, "layers": layer_results, "cases": all_cases,
              "export": {"commands": len(commands), "linear_tensors": len(layers), "linear_runs": len(all_cases),
                         "logical_s32_outputs": sum(len(v["reference_s32_f16"]) for v in all_cases),
                         "ternary_parameter_bytes_all_layers": weight_words_total * 32,
                         "largest_tensor_bytes": max(item["parameter_bytes"] for item in layer_results),
                         "workspace_high_water_bytes": 80 * 32,
                         "full_graph_on_rtl": False,
                         "unsupported_full_graph_parts": ["FP16 embedding/tied head", "affine RMSNorm gains",
                                                           "RoPE", "causal attention/softmax", "full floating point SwiGLU and residual graph"],
                         "scope": "28 real pretrained ternary linears, six captured inputs each; CPU streams one tensor at a time. No RTL text generation."}}
    (ROOT / "cpu_reference.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("LANGUAGE_CPU_EXPORT_PASS", result["parameters"], result["export"])
    for item in generations:
        print(json.dumps({key: item[key] for key in ["prompt", "continuation", "new_tokens", "cpu_seconds"]}))


if __name__ == "__main__":
    main()
