# BitNetMCU checkpoint demo

[Documentation hub](../../docs/README.md) · [Demo report](../../docs/demos/mnist.md) · [Model candidates](../../docs/demos/candidates.md) · [All tests](../README.md)

This demo uses the trained Binary-MNIST160 checkpoint. The runners, reference,
testbench, pinned asset manifests and compact results are tracked in Git.

## Reproduce

Use Python **3.12** and ModelSim. From a fresh clone, run setup once, then the demo:

```powershell
./tests/model_demo/setup.ps1 -Python 'C:/Python312/python.exe'
./tests/model_demo/run.ps1 -Python 'C:/Python312/python.exe' -SimBin 'C:/intelFPGA/20.1/modelsim_ase/win32aloem'
```

On a machine with the correct Python and simulator already selected:

```powershell
./tests/model_demo/setup.ps1
./tests/model_demo/run.ps1
```

Setup installs PyTorch **2.5.1+cpu**, NumPy **2.3.5** and Pillow **12.3.0** under
the ignored `packages/` folder. It preserves the global Python environment.
Python is discovered from PATH and then the user profile's bundled runtime;
pass `-Python` to select Python 3.12 when other versions are installed.

`fetch_assets.py` downloads public files from the commits recorded in
[upstream_manifest.json](upstream_manifest.json) and
[checkpoint_history.json](checkpoint_history.json), verifies SHA-256 before
writing, and pins the historical graph's hash. The ignored `upstream/` folder
contains the checkpoint and third-party code. A normal run verifies those files
offline; setup is the step that accesses the network. To prepare assets without
reinstalling packages, use `setup.ps1 -SkipPackages`.

```powershell
python tests/model_demo/fetch_assets.py --check
```

`export_demo.py` reads tensor metadata with a restricted pickle reader and loads
the four tensors strictly into that historical FCMNIST graph. CPU inference runs
the original PyTorch implementation. The weight exporter uses canonical CPU
float32 `sign(w - mean(w))` and retains `mean(abs(w))` as each layer's gain.
One weight lands exactly on the mean and exports as ternary zero.

## RTL protocol and checks

The host loads trained packed weights, supplied S8 images widened to S16,
descriptors and instructions. It never writes reference hidden states, q or z.
All four layers run through the existing NORM, runtime scale composition,
ternary matmul and ReLU engines. Hidden states use S16/F9 and logits S32/F16.

Ten images run with a HALT after each layer so the host can observe all **40**
layer outputs, q, z, `quant_d`, norm/quant coefficients and flags. A single
**12-instruction program including HALT** also runs the complete graph twice.
Its second run uses the same input/program/weights without reset or reload.

The completed run passed **22,492 commands and 12,402 host comparisons**;
compile and simulation each reported zero errors and warnings. Original CPU,
exported integer reference and RTL classified all ten provided examples
correctly. This is a ten-example result, not full MNIST accuracy. RTL values are
bit-exact to the integer reference; they need not equal the original float32
activations bit for bit.

## Memory and timing

- Weights: 980 SRAM words = **31,360 bytes**, leaving 1,408 bytes of 32 KiB.
- Full parameter image: 1,024 words = 32 KiB, including zero-filled spare words.
- Reserved workspace payload: **2,496 bytes**. The highest occupied byte is
  5,119 because buffers have fixed base addresses; the 8 KiB capacity is kept.
- The complete program has 11 engine instructions and one HALT: **12 total**.
- Complete active inference: **15,899 cycles** for each of the two whole-graph
  runs, excluding host load/readback. The 10 ns testbench clock does not establish
  ASIC timing. Loading is reported separately as host write counts.

## Artifacts

`parameter.mem` / `parameter.bin` contain the full SRAM image; each `.mem` row
is one 256-bit word. Binary word storage is little endian. `workspace_input_*.mem`
contain complete input SRAM images. `program.mem` and `program_layout.json`
record the program, descriptors and buffer layout. `cpu_reference.json` records
original CPU and integer intermediates. `results.json` records outcomes, hashes,
tool versions and cycle counts. `samples_predictions.png` shows the supplied
contrast-scaled S8 samples with their labels and CPU/RTL predictions.

Generated simulator logs and libraries stay local. The published result is
`results.json`; the linked [demo report](../../docs/demos/mnist.md) includes the
sample image. Setup/download scripts reconstruct the upstream assets instead
of copying third-party runtimes into the repository.
