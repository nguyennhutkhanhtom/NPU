# Parameterization: giữ nguyên functional behavior hiện có

> **Báo cáo lịch sử — đã được thay thế.** RTL hiện tại có sửa lỗi functional theo yêu cầu mới. Dùng [hướng dẫn hiện tại](../functional/README.md), [cấu hình](config.json) và [kết quả kiểm chứng mới](../functional/verification.json). Nội dung bên dưới mô tả snapshot parameterization cũ; các test legacy không phải tiêu chí pass của RTL hiện tại. `scale/run.ps1` hiện chuyển sang bộ functional test.

Phạm vi theo lựa chọn của người dùng: **chỉ parameterize; giữ nguyên cả các lỗi functional trong báo cáo review**. Bản này không áp `PATCH_PROPOSAL.md`. Các test PASS bên dưới xác nhận width, hành vi lỗi cũ và regression có giới hạn; không khẳng định coprocessor tính đúng thuật toán LLM.

## Sử dụng

- RTL đã cập nhật ở `Verilog Source code`.
- Top mặc định: `matmulfree` (tham số mặc định16-bit).
- Top scaled: `matmulfree_scaled` (8-bit, cấu hình sẵn).
- `matmul_wrap` giữ nguyên, vẫn dùng cấu hình mặc định; muốn chọn scaled trên FPGA hãy chọn top/đổi wrapper và pin constraints riêng theo board.
- Bản gốc22 file và manifest SHA-256 giữ tại `scale/baseline`. Các báo cáo ở `review/audit_20260916` mô tả snapshot trước parameterization; số dòng ở đó có thể khác file hiện tại.

```systemverilog
matmulfree #(
    .DATA_WIDTH(8), .FRAC_WIDTH(4),
    .REG_DEPTH(128), .MEM_DEPTH(16384), .INSTR_DEPTH(64),
    .MEM_INIT_FILE("mem_init_8.mem"),
    .INSTR_INIT_FILE("instruction_64.mem"),
    .SIG_INIT_FILE("sigContent_8.mif"),
    .EXP_INIT_FILE("exp_content_8.mif")
) core (...);
```

Hoặc instantiate `matmulfree_scaled` và override4 đường dẫn init file. Tất cả đường dẫn được simulator giải theo working directory. Chuỗi rỗng `INIT_FILE=""` tắt preload để testbench tự nạp; không đồng nghĩa RAM/ROM được khởi tạo zero.

## Cấu hình thực tế

| Thuộc tính | Gốc | Parameterized default | Scaled |
|---|---:|---:|---:|
| Data width | 16 | 16 | 8 |
| FRAC_WIDTH cho công thức MUL cũ | 12 | 12 | 4 |
| Word width | 512 | 512 | 256 |
| Register depth | 1024 | 1024 | 128 |
| Register pointer width | 19 | 10 | 7 |
| Main RAM depth | 524288 | 524288 | 16384 |
| Main RAM pointer width | 19 | 19 | 14 |
| Instruction depth | 512 | 512 | 64 |
| PC width | 9 | 9 | 6 |
| Ternary weights/word | 256 | 256 | 128 |
| Ternary frame words | 1024 | 1024 | 2048 |
| Ternary frame pointer | 10 | 10 | 11 |
| Accumulator width | 16 | 16 | 8 |
| SIG table entries | 65536 | 65536 | 256 |
| EXP table entries | 512 | 512 | 512 |

Giữ nguyên5 pipeline stage,13-bit ISA,8 register,32 lane,vector512,ma trận512x512, cây cộng512 phần tử/9 mức combinational và16 word/output vector. Các hằng số32/512/16 dùng cho topology không bị thu nhỏ. Main RAM logical giảm32MiB xuống512KiB; đây là dung lượng RTL khai báo, chưa phải tài nguyên FPGA sau synthesis.

Mặc định pointer register giảm19->10 theo depth1024. Với selector hợp lệ0..7, các stream vẫn nằm trong0..127; trace regression xác nhận behavior quan sát được không đổi. Không tuyên bố tương đương ở những trạng thái pointer bị force ngoài miền RAM.

## Những lỗi được giữ nguyên

- F01/F02: precedence ADD/SUB, bit chọn phép trừ và flag gating cũ.
- F03/F04: bit slicing/overflow MUL sai và DIV raw integer không rescale. Công thức MUL cũ được tổng quát hóa từ Q4.12 sang Q4.F, không thay bằng nhân fixed-point đúng.
- F06: NORM vẫn trảzero; `norm.sv` vẫn không nối vào datapath.
- F07–12: `7'd128` vẫn truncate0; memory bỏ word cuối; write/pointer không cùng gate; endpoint sống; status/reset/port-enable và FSM giữ nguyên.
- F13/F14/F26: ternary vẫn stride gấp2 số weight/word, tạo nửa mảng undriven và nửa assignment ngoài miền; capture/write lifecycle và lane output đảo vẫn giữ. Không thêm guard bits vào accumulator và không thêm pipeline stages.
- F16–19: DDR zero length, live length, END/ready/reset và address truncation vẫn giữ.
- F22–27: hazard, HALT expression, casex, nguồn dữ liệu và context TMATMUL không sửa. `ctrl_unit.sv`, `hazard_detect.sv`, `matmul_wrap.sv` khớp baseline byte-for-byte.
- Width mismatch scalar MUL overflow được làm rõ bằng một signal1-bit thay32-bit zero-extended; reduction output tương đương, không sửa lỗi flag gating. Trace mặc định kiểm cả carry/overflow.

Một lỗi có thể bị che bởi miền nhỏ hơn: EXP vẫn LUT512 entry nhưng index8-bit chỉ đạt255, nên F05 không tái hiện OOB trong profile8-bit. Profile16-bit vẫn có lỗi đó. Pointer nhỏ cũng wrap sớm hơn nếu giao dịch lỗi chạy ra ngoài miền. Không thể vừa giảm miền biểu diễn vừa giữ bit-exact tất cả trạng thái lỗi của16-bit; không có fix thuật toán hay FSM nào được áp.

Khác với profile B ban đầu trong báo cáo đề xuất sửa lỗi: **accumulator scaled là8-bit, không phải18-bit**. Đây là chủ ý để giữ overflow/wrap cũ theo chỉ dẫn mới nhất.

## DDR là module riêng

`mem_burst` thêm `LEN_BITS` (default10), `ADDR_SHIFT` (default3), giữ `MEM_DATA_BITS` và `ADDR_BITS` sẵn có. Test scaled instantiate DATA256/ADDR14/LEN4. `config.json` ghi lại profile này. Adapter chưa nối vào matmulfree và không tự thay MIG IP của FPGA.

## Kiểm chứng và chạy lại

PowerShell từ workspace:

```powershell
./scale/run.ps1                  # compile + regression + leaf tests
./scale/run.ps1 -Top Scaled      # thêm full scaled top reset/HALT smoke
./scale/run.ps1 -Top Both        # thêm default và scaled top smoke
```

Có thể override `-SimBin` và `-Python` nếu cài tool ở nơi khác. Script mặc định dùng ModelSim Intel FPGA Starter2020.1. Full core có262144 phần tử tính ternary, nên smoke rất chậm trên Starter Edition dù chỉ140ns simulation; lần chạy default mất khoảng12 phút. Script kiểm exit code và marker, không coi `$fatal` là pass chỉ vì simulator thoát0.

- `tb_replay`: cùng testbench được compile vào hai library độc lập baseline/parameterized;4096 cycle,32 lane,8 opcode, memory/register stream và flags. Hai trace phải khớp SHA-256 từng byte. Đây là regression theo stimulus, không phải formal equivalence toàn thiết kế.
- `tb_scaled_alu`:524288 so sánh, exhaustive65536 cặp operand8-bit x8 opcode; expected model giữ công thức lỗi cũ. LUT dùng identity bit pattern để kiểm địa chỉ/data width.
- `tb_scaled_storage`:512 impulse kiểm mọi lá adder tree; modulo sum; pointer register7/memory14; register word cuối; lỗi memory last-word vẫn tồn tại; frame2048 word tới endpoint16383.
- `tb_scaled_ddr`:data256/addr14/length4; read2 beat; xác nhận vẫn có address truncation và zero-length không finish.
- `tb_top`: elaborate toàn core, kiểm reset và HALT all-ones theo behavior cũ. Không phải workload TMATMUL/LLM end-to-end.

Kết quả máy đọc nằm ở `verification.json`, diff ở `parameterization.diff`, log ở `scale/sim`. Trạng thái `NOT_COMPLETED` nghĩa chưa có marker pass trong log, không phải pass. Hash RTL trong summary xác định phiên bản được bàn giao.

`scale/tools/make_fixtures.py` tạo **dữ liệu synthetic**, không phải weights, program hay LUT đúng số học của luận văn. Không dùng các file này để tuyên bố accuracy SIG/EXP/NORM. Các script review cũ trỏ vào RTL hiện tại có thể không còn phù hợp cấu hình leaf cũ; baseline cho việc tái hiện review được giữ riêng tại `scale/baseline`.

Chỉ profile8-bit và16-bit đã được kiểm trong đợt này. Không tuyên bố hỗ trợ mọi số width/depth; parameter guard từ chối một số tổ hợp không đủ RAM hoặc không đóng gói tròn frame. Chưa chạy synthesis/STA/FPGA và không sửa các functional bug còn lại.
