# Test cho source chính

[Trang bắt đầu](../README.md) · [Mục lục tài liệu](../docs/README.md) · [Kết quả kiểm chứng](../docs/verification/README.md) · [Các demo model](../docs/demos/README.md)

Legacy testbench nằm trong `tb_all.sv`; runner compile `../Verilog Source code`.
[Full graph units và application](full_rtl/README.md) có testbench riêng cho
`llm_soc`, cùng RTL nguồn. Không cần bản source v2 riêng hoặc test v1.

Runner, testbench, reference số nguyên và `results.json` được giữ trên GitHub. Cần Python 3.10 trở lên và ModelSim có `vlib.exe`, `vlog.exe`, `vsim.exe`. Python được tìm trong PATH rồi đến bundled runtime theo user profile; có thể chỉ rõ đường dẫn khi máy có nhiều bản Python:

```powershell
./tests/run.ps1 -Block All -Python 'C:/Python312/python.exe' -SimBin 'C:/intelFPGA/20.1/modelsim_ase/win32aloem'
```

Chạy từ thư mục gốc workspace:

```powershell
./tests/run.ps1 -Block All
./tests/run.ps1 -Block Norm
./tests/run.ps1 -Block Ternary
./tests/run.ps1 -Block Rowwise
./tests/run.ps1 -Block AccMul
./tests/run.ps1 -Block Sram
./tests/run.ps1 -Block DivProfiles
./tests/run.ps1 -Block Postscale
```

| Block | Nội dung |
|---|---|
| All | Tám testbench trên cùng một RTL và kiểm tra ROM bằng Python |
| Host | Toàn bộ 168 ca tích hợp qua host: NORM, TMATMUL, vector, scale động, descriptor và địa chỉ |
| Norm | NORM/QUANT, K=1…512, packing/tail, zero/full-scale, epsilon/delta, overlap và bounds |
| Ternary | Weight theo chunk, S8 extrema, bias/no-bias, S16/S32, NORM→TMATMUL, scale bị vô hiệu và descriptor sai |
| Rowwise | ADD/SUB/MUL/SIG/REC/RELU, shift, RNE, saturation, gate unsigned, tail và overlap |
| Scalar | Divider U64, sqrt 0…4095 và biên square±1, RNE, exact scale composition U128, reset/start khi busy |
| DivProfiles | NUM/DEN=1/1, 7/3, 3/7, 64/32, 64/64; exhaustive widths nhỏ, quotient/remainder, zero và input capture |
| Postscale | ACC18×U24, RNE shift 0…63, bias S32, saturation S16/S32, extrema và random |
| Sigmoid | 1.638.400 giá trị S16 cho đủ F=0…24 qua ROM constant trong `sigmoid_lut.svh`; reset/start khi busy |
| Sram | 47 kiểm tra latency hai clock, chuyển địa chỉ, mask lane, compute read và reset giữ memory |
| Imem | 1.027 checks: 512 địa chỉ, client switch, synchronous valid, overwrite/re-read, restart/reset |
| Arithmetic | Reduction tree, helper addsub/mul, biên và random |
| AccMul / AddSub / Mul | Chọn task số học riêng trong `tb_arithmetic` |

Runner compile một lần, không truyền macro chọn implementation. `-Mode` đã được bỏ; `-Suite V2` vẫn là alias cho source chính. Có thể thay đường dẫn simulator/Python bằng `-SimBin` và `-Python`. Host test chờ `host_ready` cho các memory read đồng bộ; các monitor arbitration nằm trong testbench.

`reference.py` tạo lại vector bằng Python integer/Decimal và kiểm tra chính xác 257 sample của cả `.mem` và `.svh`, bao gồm monotonic và chênh lệch hai sample liên tiếp không quá 512. Nó còn kiểm tra validator từ chối từng asset bị thiếu hoặc sai sample 128: hai ca thiếu và hai ca hỏng, bằng input mô phỏng trong Python. RTL luôn dùng ROM constant, không có tham số thay file LUT.

Scale composition được so sánh cả `(M,r)` với phép chia/làm tròn U128 độc lập, tìm `r` lớn nhất trong 0…47. Cases phủ underflow/overflow, giới hạn RNE của U24, midpoint và hai phía của midpoint; transaction hợp lệ phải hoàn tất trong 128 clock. Sqrt kiểm tra `root² ≤ x < (root+1)²` bằng tích U66 và latency 32 clock. Các test còn thay input/pulse `start` khi busy và reset giữa transaction để kiểm tra capture/cancel/restart.

Host cases thêm NORM overflow rồi descriptor sai không reset (overflow mới phải bằng 0 và output giữ nguyên), reset trong lúc divider NORM busy rồi restart, cùng/partial alias của NORM q bị từ chối nếu dùng scale static và địa chỉ ngay sau q extent vẫn hợp lệ.

`check_synthesis.tcl` là smoke check Quartus tùy chọn cho cùng source, không truyền macro. Nó kiểm tra descriptor không latch, workspace SRAM đủ 65.536 bit block RAM và instruction memory đủ 6.656 bit block RAM / không quá 128 FF trên device demo. Các con số mapping là kiểm chứng riêng cho device này.

```powershell
python tests/reference.py --check
quartus_sh -t tests/check_synthesis.tcl
```

Kết quả/source hash ở `results.json`; log ở `sim/`. Sau khi pass, runner tự xóa library ModelSim, vector sinh ra và console trùng. Dùng `-KeepBuild` nếu cần giữ chúng để debug. Khi fail, build được giữ để kiểm tra. Các test dùng dữ liệu tổng hợp, chưa thay thế kiểm chứng checkpoint model hoặc STA/PPA.

Test v1 không tương thích đã được bỏ. Các ca arithmetic còn hữu ích từ bộ cũ đã được chuyển sang interface mới: reduction N=1/3/32/37/512, số âm và extrema, saturation, signed/unsigned multiplication và RNE.

## Demo checkpoint

- [Binary-MNIST160](model_demo/README.md): setup có kiểm tra SHA-256, CPU/reference/RTL và chương trình toàn graph.
- [Model ngôn ngữ](language_demo/README.md): checkpoint, phạm vi chạy CPU và phép so sánh các tầng linear trên RTL.

Các dependency và build cache được cài/sinh riêng trong từng thư mục demo; không nằm trên GitHub. Xem [cách render sơ đồ](../tools/docs/README.md) khi chỉnh tài liệu.
