"""Export a trained BitNetMCU binary MLP to the current NPU, using NumPy.

The checkpoint reader accepts only tensor-storage metadata, not arbitrary
pickle globals. The original graph and quantizer run on a scoped CPU PyTorch
runtime; the ASIC reference uses independent integer arithmetic.
"""
from collections import OrderedDict
from dataclasses import dataclass
from hashlib import sha256
from io import BytesIO
from math import isqrt
from pathlib import Path
import json
import pickle
import re
import sys
import zipfile

import numpy as np

ROOT = Path(__file__).resolve().parent
UPSTREAM = ROOT / "upstream"
sys.path.insert(0, str(ROOT / "packages"))


@dataclass
class Storage:
    key: str
    size: int


@dataclass
class Tensor:
    storage: Storage
    offset: int
    shape: tuple
    strides: tuple


class FloatStorage:
    pass


def rebuild(storage, offset, shape, strides, requires_grad, hooks):
    return Tensor(storage, offset, shape, strides)


class TensorMetadataReader(pickle.Unpickler):
    def find_class(self, module, name):
        allowed = {
            ("collections", "OrderedDict"): OrderedDict,
            ("torch", "FloatStorage"): FloatStorage,
            ("torch._utils", "_rebuild_tensor_v2"): rebuild,
        }
        if (module, name) not in allowed:
            raise ValueError(f"Unsupported checkpoint global: {module}.{name}")
        return allowed[module, name]

    def persistent_load(self, identifier):
        kind, dtype, key, device, size = identifier
        if kind != "storage" or dtype is not FloatStorage:
            raise ValueError(f"Unsupported storage: {identifier}")
        return Storage(key, size)


def load_weights():
    checkpoint = next(UPSTREAM.glob("*.pth"))
    arrays = OrderedDict()
    with zipfile.ZipFile(checkpoint) as archive:
        metadata_path = next(name for name in archive.namelist() if name.endswith("/data.pkl"))
        prefix = metadata_path.rsplit("/", 1)[0]
        metadata = TensorMetadataReader(BytesIO(archive.read(metadata_path))).load()
        for name, tensor in metadata.items():
            if not isinstance(tensor, Tensor):
                raise ValueError(f"Unexpected checkpoint object: {name}")
            expected_strides = (tensor.shape[1], 1)
            if tensor.offset != 0 or tensor.strides != expected_strides:
                raise ValueError(f"Unsupported tensor layout: {name}")
            raw = archive.read(f"{prefix}/data/{tensor.storage.key}")
            if len(raw) != 4 * tensor.storage.size:
                raise ValueError(f"Incorrect storage size: {name}")
            arrays[name] = np.frombuffer(raw, dtype="<f4").reshape(tensor.shape).copy()
    assert list(arrays) == ["fc1.weight", "fc2.weight", "fc3.weight", "fcl.weight"]
    assert [list(w.shape) for w in arrays.values()] == [[160, 256], [160, 160], [160, 160], [10, 160]]
    return checkpoint, arrays


def load_samples():
    text = (UPSTREAM / "BitNetMCU_MNIST_test_data.h").read_text()
    samples = []
    for index, body in re.findall(r"int8_t input_data_(\d+)\[256\]\s*=\s*\{(.*?)\};", text, re.S):
        values = [int(value, 16) for value in re.findall(r"0x([0-9a-fA-F]{2})", body)]
        assert len(values) == 256
        label = int(re.search(rf"uint8_t label_{index}\s*=\s*(\d+)", text).group(1))
        samples.append((int(index), label, np.array(values, dtype=np.uint8).view(np.int8)))
    assert len(samples) == 10
    return samples


def rne(n, denominator):
    quotient, remainder = divmod(abs(int(n)), int(denominator))
    quotient += int(2 * remainder > denominator or (2 * remainder == denominator and quotient & 1))
    return -quotient if n < 0 else quotient


def sat(value, width):
    return max(-(1 << (width - 1)), min((1 << (width - 1)) - 1, int(value)))


def shift(value, count):
    return rne(value, 1 << count) if count >= 0 else int(value) << -count


def norm_reference(values):
    total = sum(int(value) ** 2 for value in values)
    rms = isqrt((total << 32) // len(values))
    nr = max(0, rms.bit_length() - 1 - 9) if total else 0
    nm = rne(1 << (32 + nr), rms) if total else 0
    z = [sat(shift(int(value) * nm, nr), 24) for value in values]
    denominator = max(1, max(abs(value) for value in z))
    qr = max(r for r in range(48) if (127 << r) <= denominator * ((1 << 24) - 1))
    qm = rne(127 << qr, denominator)
    quantized = [sat(shift(value * qm, qr), 8) for value in z]
    return quantized, z, {"quant_d": denominator, "norm_m": nm, "norm_r": nr, "quant_m": qm, "quant_r": qr}


def fixed_coefficient(value):
    numerator, denominator = float(value).as_integer_ratio()
    for r in range(47, -1, -1):
        m = rne(numerator << r, denominator)
        if 0 < m < (1 << 24):
            return m, r
    raise ValueError("Coefficient cannot be represented")


def composed_coefficient(d, factor_m, factor_r):
    for r in range(47, -1, -1):
        m = rne(d * factor_m * (1 << r), (127 << 16) * (1 << factor_r))
        if 0 < m < (1 << 24):
            return m, r
    raise ValueError("Composed coefficient cannot be represented")


def original_model(arrays):
    import importlib.util
    import torch
    torch.set_num_threads(1)
    specification = importlib.util.spec_from_file_location("checkpoint_source", UPSTREAM / "historical_BitNetMCU.py")
    source = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(source)
    model = source.FCMNIST(160, 160, 160, QuantType="Binary", WScale="PerTensor", NormType="RMS")
    model.load_state_dict({name: torch.from_numpy(weights) for name, weights in arrays.items()}, strict=True)
    model.eval()
    return model


def make_layers(arrays, model):
    import torch
    layers = []
    weight_base = 0
    for index, (name, weights) in enumerate(arrays.items()):
        source_layer = getattr(model, name.split(".")[0])
        with torch.no_grad():
            mean = float(source_layer.weight.mean())
            binary = (source_layer.weight - source_layer.weight.mean()).sign().numpy().astype(np.int8)
            magnitude = float(source_layer.weight.abs().mean().clamp_(min=1e-5))
            assert np.array_equal(source_layer.weight_quant(source_layer.weight).numpy(),
                                  binary.astype(np.float32) * np.float32(magnitude))
        frac = 9 if index < 3 else 16
        factor_m, factor_r = fixed_coefficient(magnitude * (1 << frac))
        n, k = weights.shape
        words = n * ((k + 127) // 128)
        layers.append({"name": name, "k": k, "n": n, "magnitude": magnitude, "binary_threshold": mean,
                       "weight_codes": {str(code): int(np.count_nonzero(binary == code)) for code in [-1, 0, 1]},
                       "factor_m": factor_m, "factor_r": factor_r, "frac": frac,
                       "weight_base": weight_base, "weight_words": words, "binary": binary})
        weight_base += words
    assert weight_base == 980 and weight_base <= 1024
    return layers


def float_reference(values, model):
    import torch
    with torch.no_grad():
        x = torch.tensor(values.astype(np.float32)).reshape(1, 256)
        activations = [value[0].numpy().tolist() for value in model.get_activations(x)]
        prediction = int(model(x).argmax(dim=-1)[0])
    return prediction, activations


def integer_reference(values, layers):
    x = [int(value) for value in values]
    activations = []
    for index, layer in enumerate(layers):
        quantized, scratch, metadata = norm_reference(x)
        m, r = composed_coefficient(metadata["quant_d"], layer["factor_m"], layer["factor_r"])
        dot = layer["binary"].astype(np.int64) @ np.array(quantized, dtype=np.int64)
        width = 16 if index < 3 else 32
        raw = [shift(int(value) * m, r) for value in dot]
        assert all(-(1 << (width - 1)) <= value < (1 << (width - 1)) for value in raw), "Postscale saturation"
        x = [max(value, 0) if index < 3 else value for value in raw]
        activations.append({"values": x, "quantized": quantized, "scratch": scratch, "metadata": metadata,
                            "postscale_m": m, "postscale_r": r})
    return int(np.argmax(x)), activations


def export_host(layers, samples):
    commands = []
    def emit(op, a=0, b=0, c=0):
        commands.append(f"{op:x} {a:08x} {b & 0xffffffff:08x} {c & 0xffffffff:08x}")
    def write(address, value):
        emit(1, address, value)
    def check(address, value):
        emit(2, address, value, 0xffffffff)
    def packed(values, width):
        per = 256 // width
        mask = (1 << width) - 1
        return [sum((int(value) & mask) << (width*j) for j,value in enumerate(values[i:i+per]))
                for i in range(0, len(values), per)]
    def memory(base, values, width, read=False):
        for offset, word in enumerate(packed(values, width)):
            for lane in range(8):
                (check if read else write)(0x10000 + (base+offset)*32 + lane*4, (word >> (32*lane)) & 0xffffffff)
    def workspace(identifier, base, length, fmt, frac):
        write(0x20000 + identifier*16, (base<<24)|(length<<14)|(fmt<<12)|(frac<<7))
    def instruction(op, dst, src1, src0):
        return (op<<9)|(dst<<6)|(src1<<3)|src0
    def program(words):
        for pc, word in enumerate(words + [0x1e00]):
            write(0x30000 + pc*4, word)
    def setup(sample, case_id):
        emit(7, case_id, sample["label"])
        emit(0)
        for identifier, base, length, fmt, frac in [(0,0,256,1,0),(1,96,256,0,0),
            (2,32,160,1,9),(3,64,160,1,9),(4,96,160,0,0),(5,80,10,3,16)]:
            workspace(identifier, base, length, fmt, frac)
        write(0x40010, 128)
        for index, layer in enumerate(layers):
            # reserved bit0 enables runtime q scale, bit1 omits bias.
            value=(layer["weight_base"]<<86)|(layer["k"]<<66)|(layer["n"]<<56)|\
                  (layer["factor_m"]<<32)|(layer["factor_r"]<<26)|(int(index==3)<<25)|3
            for word in range(3):
                write(0x20100+index*16+word*4,(value>>(32*word))&0xffffffff)
        memory(0, sample["input"], 16)
    def check_layer(index, state):
        memory(96, state["quantized"], 8, True)
        memory(128, state["scratch"], 32, True)
        memory([32,64,32,80][index], state["values"], 32 if index==3 else 16, True)
        meta=state["metadata"]
        check(0x40020, (meta["quant_r"]<<24)|meta["quant_m"])
        check(0x40024, (meta["norm_r"]<<24)|meta["norm_m"])
        check(0x40028, meta["quant_d"])
    stages=[]
    for index, (src,q,dst) in enumerate([(0,1,2),(2,4,3),(3,4,2),(2,4,5)]):
        stage=[instruction(7,q,0,src), instruction(8,dst,index,q)]
        if index<3:
            stage.append(instruction(12,dst,0,dst))
        stages.append(stage)
    parameter_words=[]
    for layer in layers:
        for row in layer["binary"]:
            codes=[3 if int(value)<0 else int(value) for value in row]
            parameter_words.extend(packed(codes,2))
    assert len(parameter_words)==980
    parameter_words.extend([0]*(1024-len(parameter_words)))
    (ROOT/"parameter.mem").write_text("".join(f"{word:064x}\n" for word in parameter_words), encoding="utf-8", newline="\n")
    emit(0)
    for address, word in enumerate(parameter_words):
        for lane in range(8):
            write(address*32+lane*4,(word>>(lane*32))&0xffffffff)
    for sample in samples:
        setup(sample, sample["sample"])
        for index, state in enumerate(sample["integer_states"]):
            emit(8,index)
            program(stages[index])
            write(0x40000,1)
            emit(3,200000,2,15)
            check_layer(index,state)
            check(0x40004,len(stages[index]))
        emit(9,sample["label"],sample["float_prediction"],sample["integer_prediction"])
        workspace_words=[0]*256
        for offset, word in enumerate(packed(sample["input"],16)):
            workspace_words[offset]=word
        (ROOT/f"workspace_input_{sample['sample']}.mem").write_text("".join(f"{word:064x}\n" for word in workspace_words), encoding="utf-8", newline="\n")
    # One whole-graph program runs twice without reload/reset between runs.
    sample=samples[0]
    setup(sample,10)
    program([word for stage in stages for word in stage])
    for repeat in range(2):
        emit(8,4+repeat)
        write(0x40000,1)
        emit(3,200000,2,15)
        check_layer(3,sample["integer_states"][3])
        check(0x40004,sum(len(stage) for stage in stages))
        emit(9,sample["label"],sample["float_prediction"],sample["integer_prediction"])
    (ROOT/"host_vectors.txt").write_text("\n".join(commands)+"\n", encoding="utf-8", newline="\n")
    return {"commands":len(commands),"sample_count":10,"intermediate_layers_checked":40,
            "whole_graph_repeats":2,"workspace_high_water_word":160,"workspace_high_water_bytes":5120,
            "workspace_live_payload_bytes":2496,"parameter_image_bytes":32768,
            "program_instruction_count":12}


def main():
    checkpoint, arrays = load_weights()
    model = original_model(arrays)
    layers = make_layers(arrays, model)
    samples = load_samples()
    results = []
    for index, label, values in samples:
        float_prediction, float_states = float_reference(values, model)
        integer_prediction, integer_states = integer_reference(values, layers)
        results.append({"sample": index, "label": label, "float_prediction": float_prediction,
                        "integer_prediction": integer_prediction, "input": values.astype(int).tolist(),
                        "float_states": float_states, "integer_states": integer_states})
    manifest = {"checkpoint": checkpoint.name, "checkpoint_sha256": sha256(checkpoint.read_bytes()).hexdigest(),
                "graph": "RMS+S8Quant -> BinaryFC -> ReLU (3 layers), RMS+S8Quant -> BinaryFC logits",
                "original_cpu_backend": "PyTorch 2.5.1+cpu; historical FCMNIST source at checkpoint commit",
                "weight_words": 980, "weight_bytes": 31360, "parameter_capacity_bytes": 32768,
                "parameter_remaining_bytes": 1408, "hidden_frac": 9, "logit_frac": 16,
                "layers": [{key: value for key, value in layer.items() if key != "binary"} for layer in layers],
                "samples": results,
                "float_correct": sum(item["float_prediction"] == item["label"] for item in results),
                "integer_correct": sum(item["integer_prediction"] == item["label"] for item in results),
                "prediction_agreement": sum(item["float_prediction"] == item["integer_prediction"] for item in results)}
    manifest["export"]=export_host(layers,results)
    (ROOT / "cpu_reference.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("CPU_REFERENCE_PASS", {key: manifest[key] for key in ["weight_bytes", "float_correct", "integer_correct", "prediction_agreement"]})
    print("TENSORS", [(layer["name"], layer["n"], layer["k"], layer["magnitude"]) for layer in layers])


if __name__ == "__main__":
    main()
