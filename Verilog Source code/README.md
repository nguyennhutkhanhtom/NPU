# NPU — source chính

Cập nhật 30/09/2026. Đây là source chính, đã sửa và kiểm tra bằng ModelSim cùng Analysis & Synthesis của Quartus. RTL dùng số nguyên cho inference; chưa xác nhận timing/PPA hoặc binding SRAM của ASIC. Xem `docs/quartus_warnings.md` để biết kết quả FPGA đã kiểm tra.

`Verilog Source code` là nguồn đang được phát triển. Bản sao `npu_asic_v2` đã được loại bỏ khi dọn workspace; các test cần thiết đã gộp vào `tests`.

## Cấu hình đang thực thi

- Ternary core 32 PE, mỗi lần xử lý một hàng output; activation S8, weight 2 bit, accumulator S18, K=1…512.
- Weight code `00=0`, `01=+1`, `11=−1`. Code `10` trong phần dữ liệu hữu ích làm lệnh báo lỗi; padding ngoài K được bỏ qua.
- State/residual/embedding S16 với scale `2^(-F_t)`, F_t=0…24; gate U16/F15 có raw value `0x0000…0x8000`.
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

- **Bit 0 = dynamic_q:** M/r mô tả `s_weight/s_output`. Sau NORM, phần cứng tạo hệ số postscale `C ≈ (M/2^r) × D/(127×65536)` và chọn cặp U24/U6 mới bằng RNE. Mỗi workspace descriptor lưu D riêng. D là max(abs(z), delta).
- **Bit 1 = no_bias:** bỏ đọc bias SRAM và dùng bias=0.

Khi dynamic_q=0, M/r đã là toàn bộ hệ số `s_input*s_weight/s_output`, dùng cho q được host nạp sẵn. Một tensor vừa tạo bởi NORM phải dùng dynamic_q=1; nếu thiếu scale, lệnh báo lỗi. Ghi đè vùng q làm mất hiệu lực scale tương ứng. Ghi descriptor qua host xóa toàn bộ cache scale; nên nạp tất cả descriptor trước khi chạy chương trình.

Bias S32 luôn tính theo đơn vị output và cộng **sau** rescale. r nằm trong 0…47. Hệ số không biểu diễn được trong U24/U6 bị từ chối, không tự cắt bit. Scale S8 sau NORM là scale động D/(127×65536), không lấy từ trường F_t của descriptor S8.

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

Project Quartus `quartus/matmul_free.qpf` define `SYNTHESIS` và `QUARTUS_SYNTHESIS`. Với cấu hình này, đọc parameter/workspace SRAM mất hai cạnh lên clock: host giữ `host_en=1`, `host_we=0` và địa chỉ ổn định đến khi `host_ready=1`, rồi lấy `host_rdata`. Tín hiệu ready chỉ xác nhận dữ liệu của địa chỉ đang yêu cầu. Các window control/descriptor/instruction vẫn đọc trực tiếp; ghi host được chấp nhận theo tín hiệu ready. Khi không define `QUARTUS_SYNTHESIS`, mô hình giữ host SRAM read asynchronous.

`epsilon_raw32` là một thanh ghi chung. Nếu các NORM có F_t hoặc epsilon khác nhau, exporter/host phải lập lịch cập nhật thanh ghi này giữa các đoạn chương trình; chưa có epsilon riêng trong descriptor.

## LUT

`sigmoid_257.mem` chứa 257 mẫu `RNE(0x8000*sigmoid(-8+i/16))`. Các mẫu gốc đã đúng; lỗi đã sửa nằm ở coordinate conversion và RNE khi nội suy.

- Mẫu đầu/cuối: `0x000B`/`0x7FF5`; mẫu giữa: `0x4000`. Giá trị ngoài [-8,8] được clamp về hai mẫu biên.
- `sigmoid_lut.svh` chứa cùng dữ liệu ở dạng ROM mặc định, nên runtime không phụ thuộc working directory.
- Khi define `SYNTHESIS`, ROM dùng bảng `case` hằng với một địa chỉ đọc chung cho hai mẫu kế tiếp; không cần `initial`, `$readmemh` hoặc nạp file trên ASIC. File override chỉ phục vụ mô phỏng và phải khớp bảng hằng.
- Nội suy dùng coordinate 64 bit và 24 bit phần lẻ để giữ chính xác mọi input S16 với F_t=0…24. RNE áp dụng cho toàn bộ giá trị nội suy, bao gồm parity của mẫu đầu.
- Có thể đặt parameter SIG_LUT_FILE khi mô phỏng. File thiếu, sai số mẫu hoặc sai giá trị bị báo fatal rõ ràng. Dữ liệu file luôn phải khớp ROM đã chốt.
- LUT Q4.12 và các file `.bak` cũ đã được loại bỏ vì không tham gia datapath hiện hành. ROM dùng hiện tại là `sigmoid_257.mem` và `sigmoid_lut.svh`.

Tái tạo/kiểm tra ROM: `python tests/reference.py --rtl "Verilog Source code" --check`.

## Build và regression

Thư mục `tests` và project `quartus` được giữ local theo cấu hình repository; bản clone GitHub chứa source chính và tài liệu. Các lệnh dưới đây chạy trong workspace local có bộ test.

Chạy từ thư mục gốc repository:

```powershell
./tests/run.ps1 -Block All
```

Script dùng ModelSim tại `C:/intelFPGA/20.1/modelsim_ase/win32aloem`, compile package trước module, đặt include path cho LUT và so bit-exact với reference Python số nguyên. Có thể đổi `-SimBin` trong `tests/run.ps1`. Log nằm ở `tests/sim/`; kết quả và hash nguồn nằm ở `tests/results.json`. Chọn từng khối bằng `-Block Host`, `Norm`, `Ternary`, `Rowwise`, `Scalar`, `Sigmoid`, `Sram`, `Arithmetic`, `AccMul`, `AddSub` hoặc `Mul`.

Regression chạy nhánh thường, nhánh `SYNTHESIS`, và đúng hai macro của project Quartus. Nhánh Quartus chạy module `tb_sram` trong `tests/tb_all.sv` để kiểm tra latency, đổi địa chỉ host liên tiếp, mask ghi từng lane, compute read và reset giữ dữ liệu SRAM. Chạy Analysis & Synthesis bằng Ctrl+K trong project Quartus sau khi regression pass.

Kiểm tra suy luận phần cứng riêng: `quartus_sh -t tests/check_synthesis.tcl`. Script xác nhận descriptor không có latch và wrapper SRAM 256×256 ánh xạ đủ 65.536 bit vào block RAM. Trong nhánh Quartus, SRAM được chia thành tám bank 32 bit có write-enable riêng; descriptor dùng thanh ghi 32 bit với index hằng cho từng word để tránh lỗi suy luận của Quartus 18.1.

`matmul_wrap` giữ CLOCK_50/SW/LEDG và bổ sung host ports. LED0=ready, LED1=overflow, LED2=error. Pin assignment của board phải bổ sung các host ports nếu dùng wrapper này.

Các pipeline register/ctrl_unit/hazard_detect và mem_burst được giữ để tham khảo/migration; top v2 không instantiate chúng. Các regression v1 dùng interface cũ đã được loại bỏ; test hiện tại nằm trong một file `tests/tb_all.sv`.

## Cách tổ chức RTL và thay đổi để hỗ trợ ASIC

- Các state machine và phép gán đã tách dòng; tên thanh ghi như `source_a_q`, `input_desc_q`, `vector_length_q` mô tả dữ liệu được giữ qua chu kỳ. Tên opcode thay cho số trực tiếp trong vector unit.
- `rowwise_op` dùng chung **hai phép nhân unsigned 16×16** cho MUL và REC bằng mux toán hạng, rồi khôi phục dấu. Khi không dùng, toán hạng multiplier được giữ bằng 0 để giảm switching. Đây là sharing trong vector unit; các engine khác vẫn có phép nhân riêng.
- `regfile` và `mem_mapping` dùng chung `sram_256_wrapper`: một đường ghi có mask 8×32 bit, read-valid theo latency hiện hành và kiểm tra xung đột host/compute trong mô phỏng. Memory array không nằm trong process có asynchronous reset và không được reset toàn bộ.
- Wrapper là ranh giới để thay bằng SRAM macro. Nhánh `QUARTUS_SYNTHESIS` dùng chung một cổng đọc synchronous cho host/compute và cổng ghi có mask; register dữ liệu đọc không có asynchronous reset để hỗ trợ suy luận block RAM. Nhánh ASIC mặc định vẫn dùng host read asynchronous; binding SRAM macro cần đáp ứng đúng handshake tương ứng.
- Regression chạy nhánh mô phỏng, nhánh define `SYNTHESIS` và nhánh `SYNTHESIS` + `QUARTUS_SYNTHESIS`. Đây là kiểm tra chức năng của các nhánh RTL; report Analysis & Synthesis gần nhất của Quartus được giữ trong `docs/quartus_synthesis.rpt`, chưa xác nhận Fitter hoặc STA.

## Giới hạn triển khai ASIC hiện tại

Mô phỏng xác nhận chức năng số học và giao tiếp trong các ca đã chạy. Chưa có checkpoint model hoàn chỉnh, synthesis, STA, area/power, DFT hoặc binding PDK SRAM.

Đặc biệt, **hai lane xử lý không chứng minh netlist chỉ có hai multiplier 16×16**: RTL hiện còn phép nhân rộng ở NORM, coefficient composition, postscale và nội suy. Chưa có arbitration/resource sharing xuyên các engine. Các memory array hiện là mô hình RTL có host access, chưa phải SRAM macro một cổng. Hai điểm này phải được hiện thực/đánh giá khi chuyển bản chức năng sang bản ASIC tối ưu diện tích; không được dùng kết quả regression để khẳng định đã đạt ngân sách phần cứng trong tài liệu kiến trúc.
