# Review toàn RTL và sửa ADD/SUB - 2026-09-17

Đã đọc toàn bộ 22 file RTL trong `Verilog Source code` và đối chiếu kiến trúc/hành vi trong PDF. Đợt này sửa **F01, F02: phép cộng/trừ và chọn cờ ALU**, theo lựa chọn của người dùng: **wrap kết quả và báo overflow**, không saturation. Có 25 nhóm phát hiện/rủi ro còn lại, gồm cả các vấn đề phụ thuộc hợp đồng số học/giao tiếp; chưa thể xác nhận toàn coprocessor đúng chức năng.

**Trạng thái workspace cần lưu ý:** trước khi sửa, cả 22 file đang khớp byte-for-byte với `scale/baseline`. Báo cáo `functional/verification.json`, `functional/CONTRACT.md` và `scale/CURRENT.md` mô tả một phiên bản RTL khác; 23 mục RTL trong manifest functional đều khác hoặc không còn tồn tại. `matmulfree_scaled.sv` hiện không có. Không dùng PASS cũ làm bằng chứng cho code hiện tại. Các tài liệu và thay đổi có sẵn được giữ nguyên.

Không có thư mục tên `scaled-down`; tài liệu cấu hình tương ứng nằm ở `review/audit_20260916/SCALED_CONFIG.md`, `scaled_profiles.sv` và `scale`. Bản kiểm chứng mới là [verification.json](verification.json), bằng chứng phạm vi/hashes là [audit.json](audit.json), diff chỉ của đợt sửa này là [addsub.patch](addsub.patch).

## Mục tiêu và nguồn đặc tả

- `DTUT-242-13.pdf`: chương 4, trang PDF 41-63; ISA trang 43-45; ALU trang 54-56; memory map trang 57-60; hazard trang 61-62. Hệ thống có 5 stage Fetch/Decode/Execute/Memory/Write Back, ISA 13-bit, 8 vector register, 32 lane/word, 512 phần tử/vector, ma trận ternary 512x512.
- ADD/SUB phải tính từng lane của hai vector; NORM phải dùng RMS của cả vector; TMATMUL dùng trọng số -1/0/+1 và chỉ hoàn tất sau khi ghi đủ kết quả. HALT được định nghĩa bởi opcode `1111`.
- `Nguyen Nhut Khanh_poster.pdf`, trang 1: xác nhận cùng pipeline và tính toán ternary. Đã xem trực quan poster và các trang ISA/memory của luận văn, đọc phần mô tả ALU trực tiếp từ PDF.
- PDF nêu fixed-point 16-bit. Q4.12 cụ thể đến từ comment của `mul.sv`. Q4.4 là mục tiêu thu nhỏ của báo cáo cấu hình. PDF không chốt overflow/rounding/epsilon/divide-by-zero; lựa chọn **wrap + cờ overflow cho ADD/SUB** đã được người dùng xác nhận trong phiên này. Không áp lựa chọn saturation trong tài liệu functional cũ.

## Các lỗi còn mở, ưu tiên theo tác động

P1: sai kết quả/mất dữ liệu hoặc không hoàn tất trong luồng dự kiến. P2: biên, cấu hình, mô hình X hoặc phụ thuộc hợp đồng chưa xác nhận. SIM: tái hiện ở module/truth-table; STATIC: suy từ code/index/nối dây; CONTRACT: cần chốt quy tắc sử dụng. ID giữ theo review cũ để truy vết, nhưng trạng thái ở đây đã đối chiếu với mã hiện tại.

| ID / mức | Vị trí RTL | Trigger, lỗi và tác động | Bằng chứng / hướng sửa |
|---|---|---|---|
| F13 / P1 | `ternary_mul.sv:53` | Word 512-bit chứa 256 weight 2-bit nhưng index dùng `i*512+j`. Có **131072 assignment ngoài mảng và 131072 phần tử hợp lệ không được drive**; `default` của ternary case có thể che X bằng zero. | STATIC, enumerate toàn miền trong `audit.json`. Dùng stride bằng weight/word. |
| F25 / P1 | `matmulfree.sv:291`, `mem_mapping.sv:42`, `ternary_mul.sv:28` | Port0 đọc ma trận dài nhưng nối vào buffer activation 16-word; port1 activation lại nối vào buffer weight. Ngoài ra STV normal ghi 0..1023 trong khi TM activation đọc 1024..1151, nên STORE kết quả NORM rồi TMATMUL có thể đọc dữ liệu khác. | STATIC. Thống nhất memory map, source fields và đổi routing phù hợp. |
| F14 / P1 | `ternary_mul.sv:27`, `ternary_mul.sv:96`, `matmulfree.sv:214` | Capture mọi clock `enable`, không input-valid; activation quay vòng và pointer không restart theo transaction. Khi `read_finish` pulse, output write-enable có thể chỉ kéo dài hai cycle. Top thoát RUN ngay lúc bắt đầu ghi, chưa đủ 16 word. | STATIC theo chu kỳ. Tách valid/ready/done, đếm last accepted beat. |
| F27 / P1 | `matmulfree.sv:190` | Snapshot địa chỉ/enables cập nhật mỗi clock; lệnh sau có thể thay context TMATMUL khi transaction còn chạy, kể cả khi pipeline stall. | STATIC. Latch tại start và hold đến done. |
| F26 / P1 | `ternary_mul.sv:120`, `matmulfree.sv:122` | Output concatenate row0 ở MSB trong khi consumer lấy lane0 ở LSB: đảo từng nhóm 32 phần tử. | STATIC. Pack theo `lane*DATA_WIDTH +: DATA_WIDTH`; test identity + lane marker. |
| F06 / P1 | `rowwise_op.sv:88`, `norm.sv:1` | NORM decode `111` nhưng mux không có case, toàn bộ output zero. `norm.sv` không nối vào datapath và LUT unary không thể tính RMS của 512 phần tử. | SIM. Cần thống kê full vector, sqrt/div, buffering và chốt epsilon. |
| F03 / P1 | `mul.sv:19`, `mul.sv:23` | Với Q4.12, 1*1 ra `0x1100` thay vì `0x1000`; -1*1 bị coi overflow và ra `0xffff`. Slice fractional sai và kiểm sign extension âm như overflow. | SIM. Signed product đủ rộng, rescale đúng và kiểm phạm vi sau rescale. |
| F04 / P1/P2 | `div.sv:11` | Raw integer division khiến Q4.12 1/1 ra raw1 thay vì4096; b=0 ra X; MIN/-1 wrap không có flag. | SIM + CONTRACT. Mở rộng numerator trước shift, chốt rounding và zero-divisor. |
| F05 / P1 | `exp.sv:6`, `exp.sv:21` | Bảng 512 entry nhưng index 16-bit phủ 65536 giá trị. Input0 đọc index32768; **65024/65536** input ngoài bảng. | SIM + STATIC. LUT full domain hoặc mapping có scale/range rõ ràng; cắt index đơn thuần tạo alias. |
| F07 / P1 | `mem_mapping.sv:74` | `7'd128` truncate thành0 trước phép nhân, mọi vector bank alias bank0. | SIM. Constant đủ width và derive bank stride. |
| F08 / P1 | `mem_mapping.sv:181`, `mem_mapping.sv:205` | End=base+15 nhưng điều kiện ghi là `!fifo_full`; chỉ ghi 15/16 word. | SIM: mem30 ghi, mem31 giữ nguyên. Cho last beat được commit trước done. Không áp kết luận này cho regfile: regfile có ghi cycle cuối. |
| F09 / P1/CONTRACT | `mem_mapping.sv:191`, `mem_mapping.sv:205`, `regfile.sv:173` | RAM pointer tiến khi w_en=0; trong TM mode RAM vẫn ghi khi tmatmul_write=0. Regfile ghi mọi cycle RUN dù w_en hạ. | SIM. Mapper cần một điều kiện accepted-write thống nhất. Với regfile, việc hạ w_en có pause hay chỉ là start pulse phải được chốt; không tự gọi mọi fixed-length stream là lỗi. |
| F10 / P1 | `mem_mapping.sv:109`, `mem_mapping.sv:139`, `regfile.sv:220` | Endpoint đọc/mode phụ thuộc descriptor sống; đổi selector/mode giữa burst có thể dời end ra sau pointer, chạy quá RAM và chỉ hồi phục sau wrap. Almost flags của regfile cũng dùng địa chỉ sống. | SIM: pointer vượt8191 tại depth8192. Latch descriptor khi accept và derive flags từ descriptor đó. |
| F22 / P1 | `hazard_detect.sv:19`, `hazard_detect.sv:24`, `hazard_detect.sv:36`, `hazard_detect.sv:77` | Không so producer/destination với source để bảo vệ RAW; TMATMUL kế tiếp không được hazard0 chặn; read_done nhả hazard trước write_done; LDV vẫn có thể bị flush WB. hazard2 dùng opcode all-ones, không phải STV như comment. | SIM truth-table + STATIC integration; chưa gọi là full-program proof. Cần giữ ownership/context đến commit cuối. |
| F15 / P1/P2 | `ternary_mul.sv:70`, `acc_mul.sv:8` | Negate MIN trong 16 bit vẫn ra MIN; toàn cây cộng chỉ 16 bit, 512 số Q4.12 bằng1 thành0. Không có overflow output. | SIM + CONTRACT. Wrap là đúng nếu cố ý định nghĩa modulo toàn bộ dot-product; nhưng mất giá trị tổng rộng cho quantization/RMS. Chốt policy TMATMUL riêng; sign-extend trước negate và tích lũy đủ guard bits nếu cần tổng chính xác. |
| F23 / P2 | `matmulfree.sv:309` | `ready=&instr_wb` yêu cầu cả13 bit bằng1; HALT `1111_000_000_000` trong ISA không bật ready. | SIM biểu thức + STATIC top. Decode opcode, đợi pending write hoàn tất. |
| F11 / P2 | `mem_mapping.sv:137`, `mem_mapping.sv:219`, `mem_mapping.sv:230` | Request chỉ rd_en1 vẫn làm port0 tiến và completion phụ thuộc port0. Không có valid riêng cho hai stream. | SIM. Top hiện không yêu cầu port1-only; replay port1 có thể là chủ ý, không tự coi replay là lỗi. |
| F12 / P2 | `mem_mapping.sv:125`, `mem_mapping.sv:244`, `regfile.sv:99`, `regfile.sv:216` | Reset/idle có pointer=end=0 nên full/write_finish lên dù không có transaction. Pointer dùng reset sinh từ state. | SIM + CONTRACT. Phân biệt status level/done pulse; cần xem recovery/removal sau synthesis. Không khẳng định đã có metastability trên silicon; không cần reset toàn RAM. |
| F16 / P2 | `mem_burst.v:139`, `mem_burst.v:189` | length0 làm `len-1` thành giá trị32-bit mà counter10-bit không đạt: read/write chạy không kết thúc. Length không latch; đổi length giữa burst thay đổi giao dịch. | SIM qua >1024 cycle + descriptor-change. Reject hoặc no-op length0 và latch length. Nếu caller bắt buộc hold descriptor thì nhánh đổi length là rủi ro hợp đồng. |
| F17 / P2 | `mem_burst.v:189`, `mem_burst.v:224` | END hạ theo command cuối, không theo WDF data accept. Length1, command ready trước data-ready khiến beat dữ liệu được nhận với END=0. | SIM. Count command/data handshakes riêng, buffer dữ liệu và đặt END theo MIG burst. |
| F18 / P2 | `mem_burst.v:56`, `mem_burst.v:120` | `{addr,3'd0}` rộng ADDR_BITS+3 nhưng app_addr vẫn ADDR_BITS. ADDR_BITS6, request8 bị alias thành0. | SIM + CONTRACT về đơn vị địa chỉ. Tách request/app widths hoặc giới hạn và kiểm request range. |
| F19 / P2 | `mem_burst.v:37`, `mem_burst.v:111` | ui_clk_sync_rst không được dùng. Mất calibration chỉ freeze FSM nhưng giữ app_en/address, có thể phát lại command nếu app_rdy vẫn1. | SIM; có thể tránh bằng hợp đồng reset/ready tại integration nhưng chưa có integration đó. |
| F20 / P1 | `ins_mem.sv:9`, `mem_mapping.sv:22`, `sigmoid.sv:11`, `exp.sv:10` | Tên init tương đối phụ thuộc cwd; chưa có bộ trained weights/tokenizer/program nguyên bản chứng minh workload trong PDF. Có fixture và assets sinh của lần sửa trước, nhưng chưa tương thích mặc nhiên với RTL hiện tại. | STATIC inventory. Không lấy LUT zero hay generated demo làm bằng chứng accuracy LLM. |
| F21 / P1 | `matmulfree.sv:1`, `rowwise_op.sv:52`, `rowwise_op.sv:61`, `regfile.sv:33` | Top/pipeline/children vẫn hard-code16/512; rowwise DATA_WIDTH8 không elaborate vì array ports MUL/DIV16-bit. Regfile selector>7 thiếu default gây giữ decode cũ; pointer19-bit không theo depth. | ELAB probe mới tái hiện `vsim-3906`. Parameter xuyên hierarchy, guard depth/packing, derive pointer width. |
| F24 / P2 | `ctrl_unit.sv:23` | `casex` có thể match opcode X thành LDV, bật memory read/register write. ROM chưa init bị mô phỏng như lệnh hợp lệ. | SIM. Exact case và assertion instruction-known khi valid. Đây là rủi ro mô phỏng/robustness. |

Đối với F17: END thuộc dữ liệu cuối của **MIG request/command**, không mặc nhiên là beat cuối của toàn host burst. Nếu một UI word chứa đủ BL8 thì END phải đi cùng mỗi word đó. Tài liệu [AMD app_wdf_end](https://docs.amd.com/r/en-US/ug586_7Series_MIS/app_wdf_end) định nghĩa END theo dữ liệu đang có trên bus; [AMD Command Path](https://docs.amd.com/r/en-US/ug586_7Series_MIS/Command-Path) mô tả acceptance qua app_en/app_rdy và quan hệ timing của data/command. Adapter hiện không được instantiate trong `matmulfree`; chưa kiểm real MIG.

## F01/F02 đã sửa

Hai file sản phẩm thay đổi: `addsub.sv`, `rowwise_op.sv`. 20 file RTL còn lại giữ đúng hashes đầu phiên.

- `addsub`: thêm `DATA_WIDTH` mặc định16. Tách `b_effective = b XOR mask`; cộng trong **DATA_WIDTH+1 bit**, đưa `select` về cùng width. Điều này sửa precedence và giữ carry trước khi wrap output. select0 là a+b, select1 là a-b.
- `rowwise_op`: chọn phép trừ bằng `select == SUB`, thay vì select[0] khiến ADD001 chọn subtract và SUB010 chọn add. Truyền DATA_WIDTH xuống adder.
- Carry/borrow chỉ xuất khi ADD/SUB. Overflow mux theo opcode: ADD/SUB lấy OR 32 cờ signed, MUL lấy scalar flag hiện có; các opcode khác hiện trả0 vì chưa có flag nguồn tương ứng. Không còn OR vô điều kiện overflow MUL vào ADD/SUB.
- `mul_overflow` ở rowwise đổi từ32 bit thành1 bit cho đúng port module MUL. Không sửa công thức MUL.
- Không thêm state, reset, latency hay pipeline stage vào ADD/SUB. Output là combinational; top vẫn đưa flags trực tiếp từ Execute, chưa có cơ chế sticky/retirement flags. Mọi consumer phải lấy flag cùng thời điểm với kết quả ALU.

Hợp đồng cho W>=1 và input/control xác định:

```text
sum = (a + b) mod 2^W            khi select=0
sum = (a - b) mod 2^W            khi select=1
cout_ADD = unsigned(a)+unsigned(b) > 2^W-1
cout_SUB = unsigned(a) < unsigned(b)       // borrow, không phải no-borrow
overflow = kết quả signed chính xác nằm ngoài [-2^(W-1), 2^(W-1)-1]
```

ADD/SUB cùng định dạng Q không cần dịch fractional bit. Ví dụ Q4.4 raw0x18 + raw0x04 = raw0x1c (1.5+0.25=1.75). Wrap được giữ cả khi overflow: raw0x7f+1=0x80, overflow1; raw0x80-1=0x7f, overflow1. Unsigned borrow và signed overflow độc lập: raw0-1=0xff có borrow1, overflow0.

## Kiểm chứng mới

Chạy từ workspace:

```powershell
./review/addsub_20260917/run.ps1
& 'C:\Users\khanh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' ./review/addsub_20260917/audit.py
```

Runner dùng ModelSim Intel FPGA Starter2020.1, library riêng, lock chống chạy đồng thời, marker bắt buộc và từ chối runtime Fatal/Error. Reference scalar tính signed W+1 add/sub trực tiếp, so phạm vi bằng số; không lặp lại công thức XOR/overflow của DUT. Reference rowwise dùng số nguyên signed32-bit cho dữ liệu16-bit.

| Kiểm tra | Kết quả |
|---|---|
| Compile toàn22 file hiện tại | 0 errors; 17 compiler notices 13314/2583 về unpacked port/always_comb checking, không che warning |
| Cùng directed repro trước/sau patch | 4 quan sát sai ở baseline; 0 ở bản sửa; ADD 5+3=8, SUB 5-3=2, SUB -1-1=0xfffe, không bị MUL flag nhiễu |
| Scalar W1 | 136 kiểm tra, gồm toàn8 tổ hợp a/b/op |
| Scalar W4 | 640 kiểm tra, gồm toàn512 tổ hợp |
| Scalar W8 | **131200 kiểm tra**, gồm toàn131072 tổ hợp (65536 cặp x ADD/SUB), cộng128 biên |
| Scalar W16 | **1088704 kiểm tra**: mọi raw a với8 raw b biên cho hai phép toán,128 biên riêng và40000 deterministic random |
| Scalar W32/W64 | 40128 kiểm tra mỗi width; kiểm width lớn hơn int và biên signed |
| ctrl_unit -> rowwise, 32 lane16-bit | **1307712 kết quả và40880 lần kiểm flags**, biên riêng từng lane, toàn miền a với b biên, random và đổi opcode |
| Review baseline scaled leaf | 17/17 và20/20 điều kiện lỗi được tái hiện. Đây là37 quan sát, không phải37 lỗi độc lập hay37 functional PASS |
| rowwise DATA_WIDTH8 sau patch | **Expected elaboration failure** ở MUL/DIV array ports16-bit; được giữ trong báo cáo để không nhầm leaf ADD/SUB8 với full ALU8 |
| Phạm vi thay đổi | `audit.py` xác nhận chỉ2 file RTL thay đổi, hashes khớp phiên bản vừa test |

Các bài scalar và rowwise đều PASS. Không dùng các test legacy giữ phép toán sai làm oracle cho ADD/SUB mới. Fixture LUT zero chỉ cho phép elaborate/test arithmetic và flags; không xác nhận EXP/SIG đúng số học. ADD/SUB W16 chưa exhaustive toàn2^32 cặp operand; không có formal proof.

## Cấu hình thu nhỏ và giới hạn triển khai

| Thuộc tính | RTL hiện tại | Mục tiêu B từ SCALED_CONFIG | Trạng thái đợt này |
|---|---:|---:|---|
| Data / fractional width | 16 /12 theo MUL comment | 8 /4 | Leaf ADD/SUB8 đã pass; toàn ALU8 chưa elaborate |
| Lane / word width | 32 /512 | 32 /256 | Không đổi topology |
| Register depth / pointer | 1024 /19 | 128 /7 | Chưa parameterize storage pointers |
| RAM depth / pointer | 524288 /19 | 16384 /14 trong map đề xuất cũ | Chưa áp; cần chốt vùng vector và matrix không overlap |
| Instruction depth / PC | 512 /9 | 64 /6 | Chưa áp vào core |
| Weight/word / matrix words | 256 /1024 | 128 /2048 | Phải tăng frame pointer lên11 bit, derive stride khi scale |
| Ternary accumulator | 16 | 18 nếu giữ tổng rộng trước quantization | Chưa sửa, không suy ra policy từ lựa chọn wrap ADD/SUB |

Profile A trong báo cáo cũ dùng DATA4, register selector2/depth64, mapper depth8192 và DDR data32/address6. Các test tái hiện mới chạy các giá trị này thực sự; pointer storage vẫn19-bit và DDR length vẫn10-bit. Giảm depth không tự giảm pointer hoặc sửa FSM.

`scale/config.json` hiện ghi RAM32768/pointer15, do một phiên bản trước đã chuyển matrix base lên1024 để tách 8 vector bank khỏi 8 ma trận. Đó là **quyết định memory map khác**, không phải cùng profile16384/14. Nếu chọn map riêng như vậy, W8 cần tối thiểu1024+8*2048=17408 word; depth16384 không đủ. Đợt ADD/SUB này không tự thay memory map hoặc áp toàn bộ patch functional cũ.

Để đưa full core về profile nhỏ: parameter xuyên các pipeline/ALU children, tái tạo LUT theo format, derive packing/frame/PC/pointer widths, chốt memory map và kiểm endpoint/depth. Không nối zero-extend ngầm Q4.4 vào unit Q4.12; raw0xf0 mang nghĩa -1 trong Q4.4.

## Bao phủ 22 file và giới hạn

| Nhóm file đã đọc toàn bộ | Kết luận |
|---|---|
| addsub, rowwise_op, mul, div, exp, sigmoid, norm | F01/F02 sửa và test; F03-F06/F20/F21 còn mở. Mapping sign-bit của SIG tự nó hợp lệ nếu bảng đúng thứ tự. |
| ternary_mul, acc_mul | F13-F15/F26; đã kiểm index/reduction/lifecycle bằng static và leaf accumulator. Chưa simulate toàn ma trận/core. |
| regfile, mem_mapping | Decode, bounds, FSM, last beat, descriptors, flags và reset; F07-F12/F21. |
| ctrl_unit, hazard_detect | Toàn bộ decoder và hazard equations; F22/F24. |
| PC, ins_mem | Reset active-low phù hợp cách nối; PC wrap modulo512 cần HALT trước wrap; ROM và scale F20/F21. Không tự coi wrap là bug nếu program hợp lệ đã HALT. |
| fd_reg, de_reg, em_reg, mw_reg | Reset và hold/enable của register đã kiểm; không thấy thiếu reset trường riêng. Assignment instr_mw trùng ở em_reg là dư thừa, không phải functional bug mới. Rủi ro chính ở integration/flush và width cứng. |
| matmulfree, matmul_wrap | Toàn bộ wiring, packing, snapshot, FSM TMATMUL, flags và ready; F14/F22/F23/F25/F27. |
| mem_burst | Toàn FSM, length/count/address, command/data handshake, reset/calibration; F16-F19. |

Chưa chạy end-to-end workload token generation, formal, synthesis, timing/STA hay FPGA/real MIG. Không xác nhận throughput/accuracy/tần số của PDF từ các test này. Bước sửa tiếp hợp lý là MUL/DIV và format LUT để ALU8 elaborate, sau đó mapper/FSM và TMATMUL với scoreboard đầy đủ.
