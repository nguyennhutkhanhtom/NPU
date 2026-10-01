# Demo ngôn ngữ NanoFable

[Mục lục tài liệu](../../docs/README.md) · [Báo cáo demo](../../docs/demos/language.md) · [Các test](../README.md)

Demo sử dụng checkpoint đã train **NanoFable-1M-ternary**, model ngôn ngữ nhỏ đã được đề xuất trong tài liệu của project. CPU chạy graph đầy đủ và sinh văn bản; RTL kiểm chứng các linear ternary có weight thật. **Chưa chạy sinh văn bản toàn graph trên NPU.**

## Chạy lại từ clone mới

Cần Windows PowerShell, **Python 3.11 hoặc 3.12**, ModelSim Intel FPGA có `vlib`, `vlog`, `vsim`, và internet cho bước setup. Ví dụ từ thư mục gốc repository:

```powershell
./tests/language_demo/setup.ps1 -Python 'C:/path/to/python312/python.exe'
./tests/language_demo/run.ps1 -Python 'C:/path/to/python312/python.exe' -SimBin 'C:/intelFPGA/20.1/modelsim_ase/win32aloem'
```

`setup.ps1` tải asset đã pin và kiểm tra SHA256, cài dependencies riêng vào `tests/language_demo/packages`. Không cần model demo MNIST hoặc package của model đó. Core dependencies: PyTorch **2.5.1+cpu**, NumPy **2.3.5**, safetensors **0.6.2**, tokenizers **0.22.1**. `run.ps1` kiểm tra asset, chạy CPU/export, compile RTL, so sánh ModelSim và tạo `results.json`.

Checkpoint, tokenizer, source upstream, packages và cache simulator được tải/tạo lại; không đưa các file này lên GitHub. Model nạp bằng safetensors, không nạp pickle hoặc dùng `trust_remote_code`. Source graph upstream đã đọc và pin commit; loader giữ dequantized ternary weights gốc, không lượng tử lại weight bằng một quantizer khác.

## Nguồn và graph

- [Checkpoint và model card](https://huggingface.co/adrahmana/NanoFable-1M-ternary/tree/8bb40dbf501bbad4a12a11c5697e5ad239744539): revision `8bb40dbf501bbad4a12a11c5697e5ad239744539`.
- [Source graph](https://github.com/adit-rah/nanofable/blob/4bb4ca58421f62652f6804aa4164f5be992779e2/src/nanofable/model.py): commit `4bb4ca58421f62652f6804aa4164f5be992779e2`.
- `upstream_manifest.json` ghi SHA256 và byte size của cả 12 file tải về.

Model có **1.377.408 tham số**, 4 block, width 128, 4 attention head, context 512, tokenizer BPE 4.096 token. Graph gồm embedding/head tied, RMSNorm với gain, RoPE, causal attention, SwiGLU và residual. In-block linears là `scale × {-1,0,+1}`; embedding/head và norm gain được lưu FP16. CPU của demo tính float32 từ các giá trị checkpoint FP16, phù hợp cách load model dequantized của upstream.

## Phạm vi kiểm chứng

| Phần | Cách chạy và kết quả |
|---|---|
| Text generation đầy đủ | CPU, greedy argmax, 3 prompt, 32 token mới/prompt; mỗi prompt chạy lại và token IDs giống nhau |
| Linear ternary | RTL, tất cả 28 tensor weight đã train: q/k/v/o 128→128, gate/up 128→384, down 384→128 trong mỗi block |
| Activation test | Last token của 3 prompt ban đầu và 3 context sau generation; tổng 168 lượt linear |
| Output | 33.792 giá trị S32/F16 khớp bit-exact reference số nguyên; 95.801 command, 34.128 host check |
| ModelSim | Compile và simulation 0 error / 0 warning |
| Sai số export | Relative L2 lớn nhất 1,781%, trung bình 0,288%; max absolute 0,02284 ở output linear so với CPU |

Exporter dùng activation thật tại input của từng linear. Quantization activation là absmax/127, RNE sang S8; coefficient giữ weight scale và input scale, output S32/F16. Reference dot/RNE dùng số nguyên Python/NumPy và được so sánh qua host interface. Không thêm NORM vào graph hoặc nhận kết quả của linear đơn lẻ là kết quả sinh văn bản bằng RTL.

Weight ternary của cả 28 tensor cần **212.992 B** theo layout 2 bit với padding từng hàng, vượt 32 KiB. Từng tensor tối đa **12.288 B** nên host có thể nạp và chạy riêng; workspace high water **2.560 B**. FP16 embedding/head, affine norm gain, RoPE, attention và graph floating point đầy đủ vẫn chạy trên CPU. Tổng **679.176 clock** chỉ cộng các chương trình linear riêng; không phải latency toàn model và chưa tính host load/readback.

## Chất lượng văn bản

Ví dụ prompt `Lily had a little cat.` sinh:

```text
 She was very happy. She was so happy. She was so happy. She was so happy. She was so happy. She was so happy. She was
```

Model sinh được token nhưng có lặp và lỗi ngữ nghĩa. Demo không đo perplexity trên tập TinyStories, không chứng minh chất lượng hội thoại hoặc accuracy ngôn ngữ. Các prompt, token IDs, output nguyên văn, CPU timing, scope, source hashes và RTL cycles nằm trong `results.json`.

## File và bằng chứng

- `export_demo.py`: load graph, generation, activation capture, fixed-point reference, host vectors và weight images.
- `tb_language_demo.sv`: replay host commands qua top `matmulfree`, kiểm tra output/flags.
- `finalize.py`: kiểm tra PASS marker, counts, zero warnings/errors và ghi hashes.
- `fetch_assets.py`, `setup.ps1`, `requirements.txt`: tái tạo môi trường và asset đã pin.
- `results.json`: report nhẹ có thể đưa lên GitHub. `cpu_reference.json`, `host_vectors.txt`, `images/`, logs, packages và `work/` là dữ liệu sinh lại.
