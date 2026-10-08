"""Export the pinned trained graph and run an independent integer reference.

Server-only preparation of functional fixtures; no FPGA timing gate claim.
CPU reference inference is verification only; the RTL host driver loads only
parameters, config and prompt IDs, and never loads intermediate activations.
"""
from pathlib import Path
import argparse
import json
import math
import sys
from hashlib import sha256
from datetime import datetime, timezone
import os

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LANGUAGE = ROOT / "tests/language_demo"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path, help="Fresh fixture directory")
    parser.add_argument("--prompt", default="Once upon a time, Lily found a tiny kitten.")
    parser.add_argument("--new-tokens", type=int, default=96)
    parser.add_argument("--temperature", type=int, default=166)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--min-new", type=int, default=64)
    args = parser.parse_args()
    if sys.platform != 'linux' or not os.environ.get('SLURM_JOB_ID'):
        parser.error('Reference inference requires Linux in an approved Slurm compute allocation')
    import socket, subprocess
    nodes = subprocess.check_output(['scontrol', 'show', 'hostnames', os.environ['SLURM_JOB_NODELIST']], text=True).split()
    if socket.gethostname().split('.')[0] not in nodes:
        parser.error('Current host is outside the Slurm allocation')
    if args.output.exists():
        parser.error('Output exists; use a fresh directory to preserve fixtures/evidence')
    rtl = ROOT / 'Verilog Source code'
    source_hashes = {f.name: sha256(f.read_bytes()).hexdigest() for f in rtl.iterdir()
                     if f.suffix in ('.sv', '.svh', '.mem')}
    runner_names = ("application_tb.sv", "export_checkpoint.py")
    runner_hashes = {name: sha256((HERE/name).read_bytes()).hexdigest() for name in runner_names}
    if not (1 <= args.new_tokens <= 127 and 0 <= args.temperature <= 255
            and 0 <= args.min_new <= 128 and 0 <= args.seed <= 0xffffffff):
        parser.error('new-tokens must be 1..127, temperature 0..255, min-new 0..128 and seed U32')
    sys.path[:0] = [str(LANGUAGE / "packages")]
    import numpy as np
    from safetensors.numpy import load_file
    from tokenizers import Tokenizer

    def rne(n, shift):
        array = np.asarray(n, dtype=np.int64)
        q = array >> shift
        rem = array & ((1 << shift) - 1)
        inc = (rem > (1 << (shift - 1))) | ((rem == (1 << (shift - 1))) & ((q & 1) != 0)) if shift else 0
        return q + inc

    def clamp(n):
        return np.clip(n, -(1 << 23), (1 << 23) - 1).astype(np.int64)

    def divide_rne(n, d):
        mag = np.abs(np.asarray(n, dtype=np.int64))
        q, r = np.divmod(mag, d)
        q += (2 * r > d) | ((2 * r == d) & ((q & 1) != 0))
        return np.where(np.asarray(n) < 0, -q, q)

    def packed(values, width):
        values = [int(x) for x in np.asarray(values).reshape(-1)]
        count = 256 // width
        assert len(values) % count == 0
        mask = (1 << width) - 1
        return [sum((v & mask) << (j * width) for j, v in enumerate(values[i:i+count]))
                for i in range(0, len(values), count)]

    checkpoint = LANGUAGE / "upstream/model.safetensors"
    expected_sha = "cfa114a8e411c25e89f8b507cb5886785f89132352743f26cd23a7cbaab863ae"
    assert sha256(checkpoint.read_bytes()).hexdigest() == expected_sha
    tensors = load_file(str(checkpoint))
    embedding = tensors["tok_emb.weight"].astype(np.float64)
    row_scales = np.rint(np.max(np.abs(embedding), axis=1) / 127 * (1 << 24)).astype(np.int64)
    assert np.all((row_scales > 0) & (row_scales < (1 << 24)))
    embedding_codes = np.clip(np.rint(embedding / (row_scales[:, None] / (1 << 24))), -127, 127).astype(np.int64)
    image = [0] * 24576
    image[:16384] = packed(embedding_codes, 8)
    image[23040:23552] = packed(row_scales, 32)
    matrices = {}
    pointer = 16384
    names = ("attn.q", "attn.k", "attn.v", "attn.o", "mlp.gate", "mlp.up", "mlp.down")
    for layer in range(4):
        for matrix_id, name in enumerate(names):
            value = tensors[f"blocks.{layer}.{name}.weight"].astype(np.float64)
            unique = np.unique(value)
            assert len(unique) == 3 and unique[0] == -unique[2] and unique[1] == 0
            scale = float(unique[2])
            codes = np.rint(value / scale).astype(np.int64)
            assert np.array_equal(value, codes * scale), "Preserve trained ternary codes"
            coefficient = round(scale * (1 << 24))
            assert 0 < coefficient < (1 << 24)
            rows, columns = codes.shape
            words = packed(np.where(codes < 0, 3, codes), 2)
            image[pointer:pointer+len(words)] = words
            image[23552+layer*7+matrix_id] = pointer | (columns << 15) | (rows << 25) | (coefficient << 35)
            matrices[layer, name] = (codes, coefficient)
            pointer += len(words)
    assert pointer == 23040
    gains = []
    for layer in range(4):
        for name in ("attn_norm", "mlp_norm"):
            gain = np.rint(tensors[f"blocks.{layer}.{name}.weight"].astype(np.float64) * 4096).astype(np.int64)
            assert np.all((gain >= -32768) & (gain <= 32767))
            gains.append(gain)
    final_gain = np.rint(tensors["final_norm.weight"].astype(np.float64) * 4096).astype(np.int64)
    assert np.all((final_gain >= -32768) & (final_gain <= 32767)), 'Final norm gains must fit S16/F12'
    gains.append(final_gain)
    image[23580:23652] = packed(np.stack(gains), 16)
    angles = np.arange(128, dtype=np.float64)[:, None] / np.power(10000, np.arange(0,32,2)/32)[None,:]
    cos = np.clip(np.rint(np.cos(angles)*32768), -32768, 32767).astype(np.int64)
    sin = np.clip(np.rint(np.sin(angles)*32768), -32768, 32767).astype(np.int64)
    rope_words = packed(np.stack((cos, sin), axis=-1), 16)
    image[23652:23908] = rope_words
    sigmoid = np.array([int(x, 16) for x in (ROOT/"Verilog Source code/sigmoid_257.mem").read_text().split()], dtype=np.int64)
    exp_lut = np.array([round(math.exp(-i/16)*(1<<24)) for i in range(257)], dtype=np.int64)
    gumbel = np.array([round(-math.log(-math.log((i+0.5)/256))*65536) for i in range(256)], dtype=np.int64)
    cache_k = np.zeros((4,128,4,32), dtype=np.int64)
    cache_v = np.zeros_like(cache_k)
    random = args.seed or 1
    traces = []

    def norm(x, index):
        root = math.isqrt(int(np.sum(x*x)) // 128 + 42950)
        reciprocal = int(divide_rne(1 << 32, root))
        return clamp(rne(clamp(rne(x*reciprocal,16))*gains[index],12))

    def linear(x, layer, name):
        codes, coefficient = matrices[layer, name]
        return clamp(rne((codes @ x)*coefficient,24))

    def rotate(x, position):
        a, b = x[:, :16], x[:, 16:]
        return np.concatenate((clamp(rne(a*cos[position]-b*sin[position],15)),
                               clamp(rne(b*cos[position]+a*sin[position],15))),axis=1)

    def attention(layer, position, q, k, v):
        cache_k[layer,position] = k
        cache_v[layer,position] = v
        out = np.zeros((4,32),dtype=np.int64)
        for head in range(4):
            dot = cache_k[layer,:position+1,head] @ q[head]
            scores = np.clip(rne(rne(dot,16)*11585,16), -(1<<31), (1<<31)-1)
            delta = np.max(scores)-scores
            index = np.minimum(delta >> 12,255)
            probability = exp_lut[index] - (((exp_lut[index]-exp_lut[index+1])*(delta & 4095)+2048) >> 12)
            probability = np.where(delta >= 1048576,0,probability)
            acc = probability @ cache_v[layer,:position+1,head]
            out[head] = clamp(divide_rne(acc,int(np.sum(probability))))
        return out.reshape(-1)

    def silu(x):
        raw = np.clip(rne(x,4),-32768,32767)
        grid = np.clip(raw*16+128*4096,0,256*4096)
        index = grid // 4096
        sig = divide_rne(sigmoid[index]*4096+(sigmoid[np.minimum(index+1,256)]-sigmoid[index])*(grid%4096),4096)
        return clamp(rne(x*sig,15))

    def head(x):
        nonlocal random
        logits = rne((embedding_codes @ x)*row_scales,24)
        sampled = np.empty(4096,dtype=np.int64)
        for token in range(4096):
            noise = int(rne(int(gumbel[random >> 24])*args.temperature,8))
            sampled[token] = np.clip(logits[token]+noise,-(1<<31),(1<<31)-1)
            random ^= (random << 13) & 0xffffffff
            random ^= random >> 17
            random ^= (random << 5) & 0xffffffff
        # Mask below every representable S32 score, including all-min ties.
        sampled[0] = -(1<<63); sampled[2] = -(1<<63)
        if len(output) < args.min_new: sampled[1] = -(1<<63)
        return int(np.argmax(sampled))

    tokenizer = Tokenizer.from_file(str(LANGUAGE/"upstream/tokenizer.json"))
    prompt = tokenizer.encode(args.prompt).ids
    assert 0 < len(prompt) and len(prompt)+args.new_tokens <= 128
    output = []
    token = prompt[0]
    for position in range(len(prompt)+args.new_tokens-1):
        x = clamp(rne(embedding_codes[token]*row_scales[token],8))
        for layer in range(4):
            normalized = norm(x,2*layer)
            q = rotate(linear(normalized,layer,"attn.q").reshape(4,32),position)
            k = rotate(linear(normalized,layer,"attn.k").reshape(4,32),position)
            v = linear(normalized,layer,"attn.v").reshape(4,32)
            context = attention(layer,position,q,k,v)
            x = clamp(x+linear(context,layer,"attn.o"))
            normalized = norm(x,2*layer+1)
            gate = linear(normalized,layer,"mlp.gate")
            up = linear(normalized,layer,"mlp.up")
            mixed = clamp(rne(silu(gate)*up,16))
            x = clamp(x+linear(mixed,layer,"mlp.down"))
        if position < len(prompt)-1: token=prompt[position+1]
        else:
            token=head(norm(x,8));output.append(token)
            if token==1: break
    build = args.output.resolve()
    build.mkdir(parents=True)
    (build/"parameter.mem").write_text("\n".join(f"{word:064x}" for word in image)+"\n")
    (build/"prompt.mem").write_text("\n".join(f"{token:03x}" for token in prompt)+"\n")
    (build/"expected.mem").write_text("\n".join(f"{token:03x}" for token in output)+"\n")
    reference = {"checkpoint_sha256":expected_sha,"prompt":args.prompt,"prompt_ids":prompt,
                 "new_tokens":args.new_tokens,"temperature":args.temperature,"seed":args.seed or 1,
                 "min_new":args.min_new,"expected_ids":output,"expected_text":tokenizer.decode(output),
                 "hardware_gate":"NOT_EVALUATED", "memory_backend":"portable RAM",
                 "prepared_utc":datetime.now(timezone.utc).isoformat(),
                 "rtl_sources":source_hashes, "runner_sources":runner_hashes}
    (build/"config.svh").write_text(f"localparam integer PROMPT_COUNT={len(prompt)}, MAX_NEW={args.new_tokens}, EXPECTED_COUNT={len(output)}, TEMPERATURE={args.temperature}, SEED={args.seed or 1}, MIN_NEW={args.min_new};\n")
    reference["input_files"] = {name: sha256((build/name).read_bytes()).hexdigest()
                                for name in ("parameter.mem", "prompt.mem", "expected.mem", "config.svh")}
    assert runner_hashes == {name: sha256((HERE/name).read_bytes()).hexdigest() for name in runner_names}, "Application sources changed during export/reference"
    assert source_hashes == {f.name: sha256(f.read_bytes()).hexdigest() for f in rtl.iterdir()
                             if f.suffix in ('.sv', '.svh', '.mem')}, "RTL changed during export/reference"
    (build/"reference.json").write_text(json.dumps(reference,indent=2)+"\n")
    print(f"FULL_RTL_REFERENCE_READY: prompt={len(prompt)} continuation={len(output)}")


if __name__ == "__main__":
    main()
