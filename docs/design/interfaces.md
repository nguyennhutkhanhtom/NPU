# ISA, descriptor và host interface

[Project](../../README.md) → [Tài liệu](../README.md) → **ISA và host**

<details>
<summary>Mục lục trang</summary>

- [Cấu hình đang thực thi](#cấu-hình-đang-thực-thi)
- [Instruction 13 bit](#instruction-13-bit)
- [Descriptor và scale động](#descriptor-và-scale-động)
- [Host 32 bit](#host-32-bit)
- [LUT](#lut)
- [Build và regression](#build-và-regression)
- [Cách tổ chức RTL và thay đổi để hỗ trợ ASIC](#cách-tổ-chức-rtl-và-thay-đổi-để-hỗ-trợ-asic)
- [Giới hạn triển khai ASIC hiện tại](#giới-hạn-triển-khai-asic-hiện-tại)

</details>

RTL và tài liệu cập nhật 01/10/2026. Source chính dùng một implementation cho mô phỏng và synthesis; không chọn datapath theo `SYNTHESIS`, `QUARTUS_SYNTHESIS` hoặc thuộc tính memory riêng của Quartus. Quartus dùng để demo Analysis & Synthesis và timing FPGA. RTL dùng số nguyên cho inference; chưa xác nhận timing/PPA hoặc binding SRAM của ASIC. Xem [báo cáo rà soát và kiểm chứng](../reviews/design_review.md), [critical path/Fmax](../verification/timing/README.md), [tổng quan và sơ đồ khối](../source_guide/README.md) và [chú giải từng file](../source_guide/blocks/README.md).

`Verilog Source code` là nguồn đang được phát triển. Bản sao `npu_asic_v2` đã được loại bỏ khi dọn workspace; các test cần thiết đã gộp vào `tests`.

## Cấu hình đang thực thi

- Ternary core 32 PE, mỗi lần xử lý một hàng output; activation S8, weight 2 bit, accumulator S18, K=1…512.
- Weight code `00=0`, `01=+1`, `11=−1`. Code `10` trong phần dữ liệu hữu ích làm lệnh báo lỗi; padding ngoài K được bỏ qua.
- State/residual/embedding S16 với scale `2^(-F_t)`, F_t=0…24; gate U16/F15 có raw value `0x0000…0x8000`.
- NORM dùng chung hai multiplier S25×S25 và hai đường RNE giữa ba pass; địa chỉ weight ternary dùng pointer/stride. Xem [rà soát và số liệu tối ưu](../reviews/design_review.md).
- Scalar: sqrt radix-4 32 bước; NORM dùng divider numerator U55; compose có fit filter RNE trước divider U48/U25, tối đa một lần chia. Rowwise dùng chung hai đường scale/RNE cho ADD/SUB/MUL/RELU/REC.
- NORM + QUANT xử lý toàn vector: bình phương U32, tổng U40, mean-square/epsilon U64, căn U32, scratch S24/F16 trong ô S32, output S8.
- SRAM logic: parameter 1024×256 = 32 KiB; workspace 256×256 = 8 KiB. Instruction memory 512×13 bit tính riêng.
- Scheduler single-issue, chờ hoàn thành mỗi lệnh nhiều chu kỳ. Không dùng pipeline v1 để điều khiển datapath v2.
- K và số output của một lệnh đều bị giới hạn tối đa 512. Vocabulary lớn hơn cần cấu hình/control mở rộng; bản này chưa có streaming argmax trên chip.

S/U là signed/unsigned; bit có dấu đã gồm sign bit. F15/F16 chỉ số bit phần lẻ, không phải floating-point. NPU không có datapath FP16/BF16/FP32.

## Instruction 13 bit

`[12:9]=opcode`, `[8:6]=dst descriptor`, `[5:3]=src1/matrix descriptor`, `[2:0]=src0 descriptor`.

| Opcode | Lệnh | Hành vi |
|---|---|---|
| `0x0` | NOP | Chuyển sang instruction kế tiếp |
| `0x1` / `0x2` | ADD / SUB | Hai nguồn cùng scale; rescale sang scale đích, RNE và saturation. Hỗ trợ S16; gate U16/F15 dùng cùng format cho cả ba descriptor |
| `0x3` | MUL | S16×S16 hoặc S16×gate U16/F15; hỗ trợ cả shift trái và phải theo scale đích |
| `0x6` | SIG | S16→U16/F15 bằng LUT và nội suy |
| `0x7` | NORM | RMSNorm không affine + QUANT; S16→S8, giữ metadata scale động |
| `0x8` | TMATMUL | S8×ternary→ACC18→postscale+bias→S16/S32 |
| `0xB` | REC | Đọc `dst` như state cũ H, `src0` là candidate C, `src1` là gate F. Ghi `RNE((F*H+(0x8000-F)*C)/0x8000)` về dst; H và C cùng scale. Hai tích được cộng trước khi làm tròn |
| `0xC` | RELU | S16→S16, chặn số âm về 0 rồi rescale theo descriptor đích |
| `0xF` | HALT | Kết thúc chương trình |

DIV, EXP, LDV và STV không được scheduler hỗ trợ; gặp các opcode này thì dừng và đặt error. Scalar divider vẫn được dùng nội bộ. SiLU có thể chạy bằng SIG rồi MUL. Host thực hiện argmax/tokenization nếu ứng dụng cần. Mọi chương trình phải kết thúc bằng HALT; đi qua instruction cuối cùng mà không HALT sẽ báo lỗi thay vì quay vòng PC.

ADD/SUB/MUL/SIG/RELU hỗ trợ in-place khi base bằng nhau và format/length hợp lệ. Partial overlap bị từ chối. REC cho phép candidate trùng state, nhưng gate không được ghi đè bởi state. NORM cho phép q trùng vùng X sau khi hoàn tất lượt tạo scratch; scratch không được chồng lên X hoặc q. TMATMUL không cho output chồng lên q.

## Descriptor và scale động

Workspace descriptor 32 bit giữ layout: base `[31:24]`, length `[23:14]`, format `[13:12]` (`0x0=S8`, `0x1=S16`, `0x2=U16`, `0x3=S32`), F_t `[11:7]`, reserved `[6:0]`.

Matrix descriptor 96 bit giữ layout: weight base `[95:86]`, bias base `[85:76]`, K `[75:66]`, số output `[65:56]`, M `[55:32]`, r `[31:26]`, output S32 flag `[25]`. Hai bit trước đây reserved có nghĩa mới:

- **Bit 0 = dynamic_q:** M/r mô tả `s_weight/s_output`. Sau NORM, phần cứng tạo hệ số postscale `C ≈ (M/2^r) × D/(127× 65536)` và chọn cặp U24/U6 mới bằng RNE. Mỗi workspace descriptor lưu D riêng. D là max(abs(z), delta).
- **Bit 1 = no_bias:** bỏ đọc bias SRAM và dùng bias=0.

Khi dynamic_q=0, M/r đã là toàn bộ hệ số `s_input*s_weight/s_output`, dùng cho q được host nạp sẵn. TM scale tĩnh từ chối mọi vùng đầu vào chồng lấn với q do NORM tạo còn metadata hợp lệ, kể cả descriptor ID khác hoặc partial overlap. TM động cần metadata của đúng ID, base và length. Ghi đè vùng q làm mất hiệu lực scale tương ứng. Ghi descriptor qua host xóa toàn bộ cache scale; nên nạp tất cả descriptor trước khi chạy chương trình.

Bias S32 luôn tính theo đơn vị output và cộng **sau** rescale. r nằm trong 0…47. Hệ số không biểu diễn được trong U24/U6 bị từ chối, không tự cắt bit. Scale S8 sau NORM là scale động D/(127× 65536), không lấy từ trường F_t của descriptor S8.

## Host 32 bit

Địa chỉ là byte address, phải chia hết cho 4. Host nạp từng slice 32 bit, lane thấp trước. Các window không alias sang địa chỉ ngoài phạm vi.

| Địa chỉ | Nội dung |
|---|---|
| 0x00000000…0x00007FFC | Parameter SRAM |
| 0x00010000…0x00011FFC | Workspace SRAM |
| 0x00020000 + 16×ID | Workspace descriptor ID=0…7 |
| 0x00020100 + 16×ID + 4×word | Matrix descriptor; word=0,1,2 theo thứ tự bit thấp trước |
| 0x00030000…0x000307FC | Instruction memory; 13 bit thấp mỗi host word |
| 0x00040000 | Write bit0=1 để bắt đầu tại PC=0; read `[3:0]={error,overflow,ready,running}` |
| 0x00040004 | PC hiện tại |
| 0x00040010 | Base scratch z, mặc định `0x80` |
| 0x00040014 / 0x00040018 | epsilon_raw32, low/high 32 bit |
| 0x0004001C | delta_raw U24, bắt buộc ≥1 |
| 0x00040020 / 0x00040024 | Hệ số QUANT / NORM gần nhất, `{2'b0,r[5:0],M[23:0]}` |
| 0x00040028 | D của NORM + QUANT gần nhất |

Khi đang chạy, chỉ đọc control/status được chấp nhận. Truy cập khác hoặc địa chỉ không hợp lệ có host_ready=0 và không làm thay đổi memory. Đây là host window đơn giản, chưa phải AXI/APB bridge. Saturation thông thường đặt overflow; lỗi format, địa chỉ, hệ số hoặc opcode đặt error và dừng scheduler. Output đã ghi ở các word trước khi phát hiện lỗi dữ liệu không được rollback.

Host giữ `host_en=1`, `host_we=0` và địa chỉ ổn định đến `host_ready=1`, rồi lấy `host_rdata`. Top chốt request và response có tag: control/descriptor read cần **hai cạnh lên**, parameter/workspace SRAM và instruction read cần **bốn cạnh lên** tính từ lần sample request đầu. Ghi host vẫn được acknowledge trực tiếp khi hợp lệ và commit tại cạnh clock. Request đổi địa chỉ, hạ enable hoặc chuyển sang write hủy read cũ; chỉ đọc control/status được phép khi running.

Sau ready, nếu tiếp tục giữ cùng enable/address thì response đầu được giữ trong cache của giao dịch đó. Để poll status mới cùng địa chỉ, hạ `host_en` qua ít nhất một cạnh lên rồi yêu cầu lại, hoặc đổi địa chỉ/issue write. Data chỉ có nghĩa khi ready. Reset xóa request/response valid, mask output về zero và giữ nội dung RAM.

Backend SRAM/instruction adapter vẫn dùng read/tag/valid hai cạnh lên; hai register boundary tại frontend top tạo latency host mới. Scheduler fetch không đổi: chờ instruction valid, thêm hai chu kỳ mỗi instruction so với mô hình fetch tổ hợp cũ.

`epsilon_raw32` là một thanh ghi chung. Nếu các NORM có F_t hoặc epsilon khác nhau, exporter/host phải lập lịch cập nhật thanh ghi này giữa các đoạn chương trình; chưa có epsilon riêng trong descriptor.

## LUT

`sigmoid_257.mem` chứa 257 mẫu `RNE(0x8000*sigmoid(-8+i/16))`. Các mẫu gốc đã đúng; lỗi đã sửa nằm ở coordinate conversion và RNE khi nội suy.

- Mẫu đầu/cuối: `0x000B`/`0x7FF5`; mẫu giữa: `0x4000`. Giá trị ngoài [-8,8] được clamp về hai mẫu biên.
- `sigmoid_lut.svh` chứa cùng dữ liệu ở dạng ROM mặc định, nên runtime không phụ thuộc working directory.
- ROM luôn dùng bảng `case` hằng trong `sigmoid_lut.svh`, với một địa chỉ đọc chung cho hai mẫu kế tiếp; không cần `initial`, `$readmemh` hoặc nạp file lúc chạy.
- Nội suy dùng coordinate S45 và 24 bit phần lẻ để giữ chính xác mọi input S16 với F_t=0…24. Chênh hai mẫu kế tiếp không quá 512, dùng U10 và tích U10×U24→U34. RNE áp dụng cho toàn bộ giá trị nội suy, bao gồm parity của mẫu đầu. Tooling kiểm tra giới hạn slope khi generate/đối chiếu ROM.
- Không có parameter `LUT_FILE`/`SIG_LUT_FILE`. Thay LUT bằng cách generate lại bảng hằng và kiểm tra đủ 257 mẫu với reference trước khi build.
- LUT Q4.12 và các file `.bak` cũ đã được loại bỏ vì không tham gia datapath hiện hành. `sigmoid_lut.svh` là dữ liệu ROM trong RTL; `sigmoid_257.mem` giữ cùng các mẫu để đối chiếu và generate.

Tái tạo/kiểm tra ROM: `python tests/reference.py --rtl "Verilog Source code" --check`.

## Build và regression

Repository chứa RTL, tài liệu, runner/reference/testbench và fixture nhẹ để chạy lại. Runtime, checkpoint tải về và build cache được tạo local. Chuẩn bị ModelSim theo [hướng dẫn test](../../tests/README.md); các lệnh dưới đây chạy từ thư mục gốc repository.

Chạy từ thư mục gốc repository:

```powershell
./tests/run.ps1 -Block All
```

Script dùng ModelSim tại `C:/intelFPGA/20.1/modelsim_ase/win32aloem`, compile package trước module, đặt include path cho LUT và so bit-exact với reference Python số nguyên. Có thể đổi `-SimBin` trong `tests/run.ps1`. Log nằm ở `tests/sim/`; kết quả và hash nguồn nằm ở `tests/results.json`. Chọn từng khối bằng `-Block Host`, `Norm`, `Ternary`, `Rowwise`, `Scalar`, `DivProfiles`, `Postscale`, `Sigmoid`, `Imem`, `Sram`, `Arithmetic`, `AccMul`, `AddSub` hoặc `Mul`; không còn tham số `-Mode`.

Regression chạy một bộ RTL thống nhất. Module `tb_sram` trong `tests/tb_all.sv` kiểm tra latency, đổi địa chỉ host liên tiếp, mask ghi từng lane, compute read và reset giữ dữ liệu SRAM. Các kiểm tra misuse/handshake nằm ở testbench thay vì thay đổi RTL theo macro synthesis. Sau regression, có thể chạy Analysis & Synthesis bằng Ctrl+K trong project Quartus để kiểm tra khả năng tổng hợp.

Lượt `All` sau rà soát toàn design pass **10 mục kiểm tra** lúc 14:31:18 ngày 01/10/2026: ROM và chín testbench RTL; compile 0 error/0 warning. Gồm 168 ca host cùng 30 protocol reads/11 cancellations/4 blocked regions, 900 exact compose, 4.301 sqrt, 12.720 postscale và 1.638.400 sigmoid input ở đủ 25 F_t. Rowwise thêm 1.800 ca với reference S128, kiểm tra busy-input changes và reset trong các pha. A&S sau tối ưu timing pass 0 error/0 warning lúc 14:31:44; xem [báo cáo timing](../verification/timing/README.md) và [rà soát design](../reviews/design_review.md).

Kiểm tra suy luận phần cứng riêng: `quartus_sh -t tests/check_synthesis.tcl`. Script kiểm tra latch/RAM trong netlist demo của Quartus. SRAM được chia thành tám bank 32 bit có write-enable riêng trong mọi build; descriptor dùng thanh ghi 32 bit với index hằng cho từng word. Cách viết này mô tả enable/reset rõ ràng cho công cụ synthesis, không yêu cầu primitive hay thuộc tính Intel.

`matmul_wrap` giữ CLOCK_50/SW/LEDG và bổ sung host ports. LED0=ready, LED1=overflow, LED2=error. Pin assignment của board phải bổ sung các host ports nếu dùng wrapper này.

Các pipeline register/ctrl_unit/hazard_detect và mem_burst được giữ để tham khảo/migration; top v2 không instantiate chúng. Các regression v1 dùng interface cũ đã được loại bỏ; test hiện tại nằm trong một file `tests/tb_all.sv`.

## Cách tổ chức RTL và thay đổi để hỗ trợ ASIC

- Các state machine và phép gán đã tách dòng; tên thanh ghi như `source_a_q`, `input_desc_q`, `vector_length_q` mô tả dữ liệu được giữ qua chu kỳ. Tên opcode thay cho số trực tiếp trong vector unit.
- `rowwise_op` dùng chung **hai phép nhân unsigned 16×16** cho MUL và REC bằng mux toán hạng, rồi khôi phục dấu. Khi không dùng, toán hạng multiplier được giữ bằng 0 để giảm switching. Đây là sharing trong vector unit; các engine khác vẫn có phép nhân riêng.
- `regfile` và `mem_mapping` dùng chung `sram_256_wrapper`: một đường ghi có mask 8× 32 bit và một cổng đọc synchronous dùng chung cho host/compute. Memory array và register dữ liệu đọc không có asynchronous reset; tag/control được reset, nội dung RAM được giữ.
- Wrapper là adapter RTL chung để thay bằng SRAM macro. Khi bind macro, adapter phải giữ arbitration, mask ghi và read-valid hiện hành; nếu latency/cổng macro khác, cần điều chỉnh adapter và kiểm chứng handshake. Core không instantiate primitive FPGA hoặc gắn `ramstyle`/`M10K`.
- Cache scale chỉ reset q_valid; 336 payload bits dùng full write, enable riêng và index hằng cho từng slot, mọi consumer được gate bởi valid.
- Regression kiểm tra một implementation. Report Quartus tại `docs/verification/reports/quartus_synthesis.rpt` chỉ minh họa khả năng synthesis và ánh xạ FPGA của snapshot tương ứng; chưa xác nhận Fitter, STA hoặc PPA ASIC.

## Giới hạn triển khai ASIC hiện tại

Mô phỏng xác nhận chức năng số học và giao tiếp trong các ca đã chạy. [Demo checkpoint Binary-MNIST160](../demos/mnist.md) pass 10/10 ảnh mẫu, 40 lượt tầng bit-exact và hai lần chạy graph liên tục, giữ nguyên RTL. [Demo NanoFable](../demos/language.md) chạy 3 prompt × 32 token trên CPU và replay 168 lượt linear ternary thực trên RTL, khớp 33.792 output S32. Sinh văn bản toàn graph và các operator chưa hỗ trợ vẫn ở CPU; toàn model chưa chạy trên core. Chưa có đánh giá toàn bộ MNIST, synthesis/STA ASIC, area/power, DFT hoặc binding PDK SRAM.

Đặc biệt, **hai lane xử lý không chứng minh netlist chỉ có hai multiplier 16×16**: RTL hiện còn phép nhân rộng ở NORM, coefficient composition, postscale và nội suy. Chưa có arbitration/resource sharing xuyên các engine. Các memory array hiện là mô hình RTL synchronous có host access, chưa bind SRAM macro của PDK. Hai điểm này phải được hiện thực/đánh giá khi chuyển bản chức năng sang bản ASIC tối ưu diện tích; không được dùng kết quả regression để khẳng định đã đạt ngân sách phần cứng trong tài liệu kiến trúc.

---

[Đọc tiếp: hierarchy RTL](../source_guide/README.md) · [Kiểm chứng](../verification/README.md) · [Demo model](../demos/README.md) · [Về mục lục tài liệu](../README.md)
