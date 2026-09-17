# Review RTL theo đặc tả MatMul-free coprocessor

Ngày: 2026-09-16. Phạm vi: toàn bộ **22 file RTL** trong `Verilog Source code`, gồm 21 `.sv` và `mem_burst.v`. **Không sửa RTL sản phẩm.** Hash SHA-256 trước/sau được lưu cùng báo cáo.

Kết luận: có lỗi chức năng chắc chắn trong arithmetic, NORM, địa chỉ bộ nhớ, TMATMUL và các rủi ro điều khiển giao dịch. RTL hiện tại chưa đủ cơ sở để xác nhận thực thi đúng workload trong PDF. Việc compile thành công tất cả file không đồng nghĩa đã elaborate hoặc kiểm chứng toàn bộ top-level.

## Đặc tả dùng để đối chiếu

- `DTUT-242-13.pdf`, chương 4, trang PDF 41–63 (số trang in 30–52): pipeline Fetch/Decode/Execute/Memory/Write Back; ISA 13 bit; 8 thanh ghi vector; 32 lane x 16 bit; 512 phần tử/vector và ma trận ternary 512x512.
- ISA tại trang PDF 43–45: ADD, SUB, MUL, DIV, EXP, SIG, NORM, TMATMUL, LDV, STV, HALT. HALT được định nghĩa bằng opcode `1111`, không yêu cầu cả 13 bit bằng 1.
- Trang PDF 50–54: trọng số ternary {-1,0,+1}, tích vô hướng và ghi kết quả sau khi hoàn thành. Trang 55–56: NORM là RMS của **cả vector**, không phải hàm unary độc lập trên mỗi phần tử.
- Trang PDF 57–60, Figure 13: vector chiếm 16 word, 8 vector/index, bank stride 128 word; ma trận ternary chiếm 1024 word 512-bit.
- Trang PDF 61–62: phải xử lý dependency và giữ state khi stall. Trang PDF 67–71 có chương trình minh họa token generation.
- `Nguyen Nhut Khanh_poster.pdf`, trang 1: xác nhận cùng kiến trúc 5-stage, ternary và normalization. Đã xem trực quan poster cùng các trang ISA/memory map của luận văn.
- PDF chỉ nêu fixed-point 16-bit; Q4.12 cụ thể xuất phát từ comment `mul.sv:10`. Kết luận về scale MUL/DIV dùng hợp đồng này; rounding, saturation, divide-by-zero và epsilon của RMS chưa được đặc tả đầy đủ.
- Luận văn có vài mô tả không khớp nhau: “8 pipeline stages” trong khi giảm 512 phần tử cần 9 mức cộng; “1024 entries mỗi register” trong khi RTL chỉ decode 16 word/register. Không tự dùng các câu này để áp đặt một kiến trúc mới.

Mức độ: **P1/Cao** = sai kết quả, mất dữ liệu, không hoàn tất trên điều kiện hợp lệ/được hỗ trợ; **P2/Vừa** = lỗi biên, thiếu hợp đồng, cấu hình hoặc giao tiếp chưa tích hợp. **SIM** = tái hiện trên module RTL gốc; **STATIC** = chứng minh từ code/index hoặc nối dây; **CONTRACT** = tác động phụ thuộc hợp đồng giao tiếp/số học được ghi rõ.

## Danh sách phát hiện, theo mức ưu tiên

| ID | Severity | Phát hiện | Bằng chứng |
|---|---|---|---|
| F13 | P1 | Giải nén ternary dùng stride 512 thay vì 256 | STATIC: 131072 assignment ngoài mảng, 131072 phần tử hợp lệ không có driver |
| F25 | P1 | Hai luồng matrix/activation nối ngược vào TMATMUL | STATIC: port0 đọc 1024 word nhưng vào buffer activation 16 word |
| F14 | P1 | Ghi TMATMUL chưa đủ 16 word đã dừng; capture không có valid | STATIC: `tmatmul_write` là write-enable nhưng top dùng như completion |
| F27 | P1 | Ngữ cảnh TMATMUL bị cập nhật bởi lệnh kế tiếp | STATIC: register địa chỉ/control cập nhật mọi clock, kể cả stall |
| F26 | P1 | Đảo thứ tự 32 lane kết quả TMATMUL | STATIC: row0 ở MSB nhưng consumer coi lane0 ở LSB |
| F06 | P1 | NORM luôn xuất zero | SIM; thiếu case và thiếu datapath RMS |
| F01 | P1 | SUB trả phép cộng; chọn ADD/SUB ngược | SIM: 5-3 -> 8 |
| F03 | P1 | Nhân fixed-point sai scale, overflow âm sai | SIM: 1*1 -> 1.0625; -1*1 -> 0xffff |
| F04 | P1/P2 | DIV không rescale; zero divisor và MIN/-1 không xử lý | SIM + CONTRACT |
| F05 | P1 | EXP dùng index 16-bit cho bảng 512 entry | SIM: exp(0) đọc index32768 -> X |
| F07 | P1 | Literal `7'd128` bị truncate thành zero, alias bank | SIM: index3 -> offset0 thay vì384 |
| F08 | P1 | Bộ nhớ bỏ word cuối của mọi write burst | SIM: word30 được ghi, word31 giữ nguyên |
| F09 | P1 | Điều kiện ghi RAM khác điều kiện tiến pointer | SIM: advance khi không write; write khi TM result chưa valid |
| F10 | P1 | Endpoint/mode đang hoạt động thay đổi theo request mới | SIM: pointer vượt depth, không finish trước wrap |
| F22 | P1 | Hazard không bảo vệ đầy đủ RAW/TMATMUL/completion | SIM truth-table + STATIC integration |
| F15 | P1/P2 | Tích và accumulator ternary thiếu guard bits | SIM: 512 số Q4.12 bằng1 cộng thành0; overflow policy chưa chốt |
| F23 | P2 | HALT hợp lệ không bật `ready` | SIM biểu thức + STATIC top |
| F02 | P2 | Carry/overflow của opcode khác rò ra output | SIM; port overflow 1-bit nối 32-bit |
| F11 | P2 | Read port enables không được giữ riêng | SIM port1-only vẫn tiến port0; chưa dùng kiểu này ở top |
| F12 | P2 | Full/finish có thể lên ở idle/reset | SIM; là so sánh endpoint, không có trạng thái giao dịch |
| F16 | P2 | DDR length zero underflow và length không latch | SIM read/write zero không kết thúc; length đổi giữa burst |
| F17 | P2 | DDR WDF END kết thúc theo command, sai khi backpressure | SIM; adapter chưa nối vào top hiện tại |
| F18 | P2 | DDR address shift mất 3 bit cao | SIM: ADDR_BITS6, địa chỉ8 ->0; phụ thuộc miền địa chỉ hợp lệ |
| F19 | P2 | DDR bỏ qua UI reset, giữ command khi calibration mất | SIM; cần quy định reset chung |
| F20 | P1 | Thiếu instruction và dữ liệu/LUT gốc để chạy workload | STATIC inventory: chỉ có fixture zero trong thư mục review |
| F21 | P1 | Parameterization hiện tại không hỗ trợ scale toàn hệ thống | ELAB: DATA_WIDTH8 gây 6 lỗi array width; top không có parameter |
| F24 | P2 | `casex` biến opcode X thành load hợp lệ | SIM: reg write và memory read cùng được bật |

## Bằng chứng chi tiết

### F13 — Packing ma trận ternary

`ternary_mul.sv:46,51–54` khai báo `tmatrix_data[262143:0]`, mỗi `tmatrix[i]` chứa **256** trọng số 2-bit nhưng gán vào `i*512+j`, với i=0..1023, j=0..255. Index256..511 không được gán; i512,j0 đã là262144; index lớn nhất524031. Chính xác nửa số assignment vượt mảng, nửa số phần tử trong mảng không có driver. Case tại dòng68–71 biến weight không biết thành zero qua nhánh default, có thể che lỗi bằng kết quả số có vẻ hợp lệ. `static-evidence.json` liệt kê kết quả enumerate toàn miền. Đây là chứng minh index, không phải log elaborate full TMATMUL.

### F25 — Port matrix và activation bị tráo

`mem_mapping.sv:42–51,109–111` cho port0 đọc 1024 word ma trận, port1 đọc/replay 16 word activation. Nhưng `matmulfree.sv:291–292` nối `mem_out_0_mw` vào `matrix_in`, `mem_out_1_mw` vào `ternary_matrix`. `ternary_mul.sv:28–29` lại lưu `matrix_in` trong `matrix_x[15:0]` và `ternary_matrix` trong `tmatrix[1023:0]`. Cả hai cách diễn giải đều mâu thuẫn kích thước/packing. Với matrix và activation khác nhau, kết quả không thể là tích theo PDF. Cần xác minh mapping của file dữ liệu gốc khi sửa, không chỉ đổi tên tín hiệu.

Ngoài tráo luồng, port1 cố định đọc activation tại1024+16*selector trong khi normal STV (kể cả sau sửa F07) chỉ tới1023. Không có đường STV ghi vector vừa chuẩn hóa vào vùng activation mà port1 đang đọc. Ví dụ PDF mô tả STORE V0 rồi TMATMUL dùng V0 cần được kiểm theo mapping thống nhất. Raw program và comment ở trang PDF68 cũng có chỗ không khớp nhau (ví dụ đích bit000 nhưng comment LOAD R2); không coi đoạn minh họa đó là executable golden program nếu chưa chuẩn hóa.

### F14 — Capture và completion của TMATMUL

`ternary_mul.sv:27–42`: enable làm capture và tăng cả hai pointer **mọi clock**, không có read-valid, không chờ FETCH, không reset pointer ở đầu transaction; activation buffer bị ghi vòng suốt 1024 cycle. Top bật enable khi nhận opcode, trước khi memory FSM hoàn tất FETCH (`matmulfree.sv:213,290`; `mem_mapping.sv:137–139`). Có thể capture dữ liệu idle/word trước đó và không đồng bộ frame.

`ternary_mul.sv:96–115`: nếu read_finish chỉ pulse một cycle, từ write_ptr0 sẽ có hai cycle write_enable=1, sau đó ptr2 và write_enable=0 do `else if (|write_ptr)`. Không đạt16 output word; write_ptr chỉ reset bằng rst_n. Nếu read_finish giữ high, pointer lại có thể chạy vòng vì nhánh read_finish ưu tiên hơn nhánh tắt. Nặng hơn, `matmulfree.sv:214` thoát RUN ngay khi write_enable lên (tmatmul_write), còn `mem_in` và `rd_type` đổi theo tmatmul_assert ở dòng256,261. Start-of-write bị dùng như end-of-transaction. Đây là phân tích chu kỳ từ RTL, chưa chạy full TMATMUL.

### F27 — Transaction context không được giữ

`matmulfree.sv:180–196` ghi lại source, destination và memory enables từ `instr_em` mỗi clock; không có điều kiện “accept TMATMUL” hoặc “đang busy thì hold”. Mux dòng237–243 dùng chính register này trong suốt RUN. Lệnh kế tiếp có thể đổi operand/destination/enable của transaction dài. Ngay cả khi EM stall, snapshot sẽ nhận instruction đang gây stall chứ không giữ instruction TMATMUL gốc. Hệ quả kết hợp F10: endpoint có thể thay đổi giữa burst. `em_reg` có enable, nhưng snapshot chạy ngoài enable nên không bảo toàn cùng ngữ cảnh.

### F26 — Lane output đảo

`ternary_mul.sv:120–135` concatenate row0 trước, nên row0 nằm bits511:496 và row31 ở15:0. `matrix_in_data` dòng57 và ALU ở `matmulfree.sv:122–123,144–149` dùng phần tử0 ở bits15:0. Sau TMATMUL -> LDV -> arithmetic, các nhóm32 phần tử bị đảo. Ví dụ row0=1,row31=32 thì lane0 consumer đọc32. Chưa có phép reorder bù trong top. Cần test identity matrix với vector đánh số theo lane để bắt lỗi này.

### F06 — NORM không có implementation phù hợp

`ctrl_unit.sv:51–58` decode NORM thành alu_op111. `rowwise_op.sv:79–92` thiếu case NORM, nên cả32 lane về zero. Test nonzero input tái hiện trực tiếp. Module `norm.sv` không được instantiate và chỉ tra bảng theo một x, không thể tính RMS phụ thuộc cả512 phần tử. Chỉ thêm `.NORM: norm_out` với LUT hiện tại sẽ vẫn sai PDF. Phải có thống kê vector, sqrt/div và quy tắc epsilon/quantization trước khi có thể gọi là hoàn thiện NORM.

### F01 — SUB và precedence

`addsub.sv:10`: biểu thức được nhóm thành `(a+b) ^ ({16{select}}+select)`, không phải `a+(b^{16{select}})+select`. Dưới sizing17-bit của `{c,sum}`, select1 vẫn giữ16 bit thấp bằng a+b. Test scalar a5,b3,select1 ->8. `rowwise_op.sv:38` đưa select[0] vào adder: ADD001 chọn1, SUB010 chọn0, ngược ý định. Phải sửa cả hai chỗ; chỉ sửa precedence sẽ biến ADD thành SUB.

### F03 — MUL fixed-point và sign/overflow

`mul.sv:23–25` ghép bits26:24 thành integer nhưng lấy bits27:16 cho fractional, chồng lấn bit và bỏ sai phần lẻ. Với Q4.12: `0x1000*0x1000 = 0x01000000`; result hiện0x1100 thay vì0x1000. Giá trị đúng phải lấy sau dịch12 bit theo quy tắc rounding đã chốt. Dòng19 kiểm `|product[30:27]` xem sign-extension của kết quả âm là overflow; -1*1 tạo0xffff thay vì0xf000. Mẫu saturate0xffff không phải signed max/min. Cần kiểm các bit bỏ đi có bằng sign bit sau rescale và mở rộng signed trước thao tác.

### F04 — DIV scale, zero và overflow

`div.sv:11` chia raw signed integer: Q4.12 1/1 thành0x0001 thay vì0x1000. Phải mở rộng numerator trước khi shift FRAC_W; shift trong16-bit sẽ làm mất dữ liệu. Test b0 cho X; raw0x8000/raw0xffff cho0x8000 (overflow 32768 -> -32768). Sai scale là P1 nếu cùng định dạng fixed-point với MUL; divide-by-zero và MIN/-1 là P2 cần định nghĩa exception/saturation. Không tự đặt quy tắc thay người thiết kế.

### F05 — EXP index vượt giới hạn

`exp.sv:6–21`: mem có512 entry, y16-bit là phép flip sign bit tương đương `(a+32768) mod65536`. exp(0) truy cập32768 ->X. Chỉ raw input0x8000..0x81ff truy cập hợp lệ; **65024/65536** input ngoài bảng. Cần quyết định dùng đủ65536 entry hoặc mapping/clamp9-bit thật sự có scale. Chỉ cắt y xuống9 bit tạo alias, không phải sửa hàm exp.

### F07 — Mất index bank

`mem_mapping.sv:74`: `7'd128` cần8 bit để biểu diễn, thực tế giá trị0. Vậy v_index luôn0 cho mọi r_addr_1 trong normal mode. Test selector3 ->0, mong384 theo Figure13. LDV/STV với index khác0 đọc/ghi nhầm cùng bank. Đây là truncation của literal trước phép nhân, không phải thiếu width ở LHS.

### F08 — Word cuối write bị bỏ

`mem_mapping.sv:181,205,244`: end=base+15, fifo_full khi pointer==end, nhưng write chỉ khi !fifo_full. RUN chỉ ghi base..base+14. Test base16 với16 beat giữ w_en=1: mem30 thay đổi nhưng mem31 vẫn0. `regfile.sv:175–176` không có cùng lỗi vì ghi cả cycle cuối; không được áp kết luận này cho cả hai module chỉ vì dùng chung kiểu pointer.

### F09 — Memory write và pointer khác điều kiện

`mem_mapping.sv:191` advance không kiểm w_en, còn dòng205 ghi chỉ khi w_en và không kiểm tmatmul_write. Normal mode mất beat nếu w_en hạ giữa RUN. TM mode có thể ghi đè cùng một địa chỉ nhiều lần bằng kết quả chưa valid khi pointer bị giữ. Cả hai đã tái hiện bằng RTL gốc. `regfile.sv:174–177` tiếp tục ghi khi w_en hạ là **hợp lệ nếu w_en chỉ là start request**; test cũ gắn nhãn “contract risk”, không đủ để khẳng định riêng register bị lỗi. Cần một định nghĩa rõ start/valid cho từng interface.

### F10 — Endpoint sống và wrap

`mem_mapping.sv:109–111` không latch endpoint. Base được latch vào pointer ở FETCH nhưng địa chỉ/mode input vẫn điều khiển end và almost flags. Test đang ở7169 rồi đổi sang normal base0/end15: sau1100 cycle pointer8269, vượt depth8192, FSM còn RUN. Với pointer19-bit, phải wrap về15 mới thỏa equality, thay vì hoàn tất burst ban đầu. Đây là vòng chạy sai hữu hạn rất dài, không phải chứng minh deadlock vô hạn. Top thực tế có khả năng đổi request qua F27. Regfile latch end nhưng almost flags dòng221–222 vẫn dùng địa chỉ sống.

### F22 — Hazard/completion chưa đủ

- `hazard_detect.sv:22` không bao gồm lệnh TMATMUL kế tiếp trong hazard0; đang busy + EM=TMATMUL vẫn không stall vì hazard này. Đồng thời chỉ chờ read_finish, trong khi kết quả chưa hoàn tất ghi.
- Dòng24–28 không so sánh source/destination và không có scoreboard/valid. Test consumer ADD dùng R1 đang được LDV sản xuất, almost_empty1 -> hazard1=0. Đây là chứng minh control không phát hiện dependency, chưa phải end-to-end trace của một chương trình đầy đủ.
- Dòng36 chỉ set hazard2 khi opcode EM=1111; comment nói load/store nhưng STV không thỏa. `write_finish | full` cũng cho phép một subsystem hoàn thành che subsystem kia còn busy.
- Dòng74–75 vẫn flush WB cho LDV/STV khi read_finish1 dù hazard0 đã nhả. Có nguy cơ mất load/writeback tại ranh giới kết thúc.
- Dòng50–68 dùng `*_stall=1` với nghĩa **cho phép tiến**, khớp `PC.sv:15` và pipeline enables. Tên gây nhầm nhưng **không kết luận đây là lỗi đảo polarity**. Ngược lại giữ cùng instruction nhiều cycle có thể là chủ ý stream vector; không coi mọi repeated decode là lỗi duplicate instruction.

### F15 — Accumulator hẹp, negation và thiếu pipeline như mô tả

`acc_mul.sv:7–14,19–74` giữ16-bit ở mọi tầng. 32767+1 ->0x8000; 512 lần0x1000 ->0. `ternary_mul.sv:70` negate raw0x8000 trong16 bit vẫn ra0x8000, không biểu diễn được +32768. Nếu hợp đồng là wrap modulo2^16, đây là hành vi xác định, nhưng PDF nói phép tích/accumulate số học và không khai báo wrap. Đánh dấu P1 đối với kết quả số học, P2 đối với việc chưa có policy.

Muốn hỗ trợ toàn miền signed16-bit nhân ternary, phải sign-extend **trước** negate; conservative term17-bit +9 guard bits = accumulator26-bit. 25-bit signed không đủ cho trường hợp512 phần tử -32768 nhân -1: tổng +16777216. Nếu vẫn xuất16-bit, cần bước quantize/saturate/wrap tường minh ở cuối. Các stage hiện là combinational, không phải pipeline register; không dùng review này để xác nhận timing200MHz.

### F23 — HALT/ready

`hazard_detect.sv:44` dừng PC dựa opcode1111 nhưng `matmulfree.sv:309` ready=`&instr_wb`, đòi cả13 bit bằng1. HALT `1111_000_000_000` hợp lệ theo ISA nhưng không bao giờ báo ready khi nằm ở WB. Test chỉ kiểm biểu thức đúng nguyên văn; chưa chạy toàn pipeline. Ngoài ra ready cần gắn với drain/commit xong mọi giao dịch, không chỉ opcode đang ở WB, sau khi sửa F14/F22.

### F02 — Flag của opcode khác

`rowwise_op.sv:47–48` enable ADD flags khi bit2==bit1, tức000,001,110,111; bỏ SUB010. Dòng77 OR overflow của MUL cho mọi opcode, cả SIG/EXP/NORM. Test SIG lộ carry của phép cộng và overflow do tích âm không được chọn; SUB có carry nội bộ1 nhưng output0. `mul_overflow`32-bit ở dòng51 nối scalar1-bit tại mul.sv:5 gây warning; bản thân widening này chưa chứng minh lane overflow bị mất, vì module mul đã reduce OR nội bộ.

### F11 — Read enables và replay

`mem_mapping.sv:137,139,219,230–233`: rd_en0/1 chỉ OR để khởi động, cả hai pointer chạy và FSM kết thúc theo port0. Test rd_en1-only vẫn advance port0 từ7168 lên7169. Port1 tự reload mỗi16 word là replay có thể chủ ý phục vụ TMATMUL, **không tự coi reload này là lỗi**. Vấn đề là không có enabled/valid riêng và port1-only không có completion độc lập. Top hiện không phát request chỉ port1 nên severity P2 ở interface.

### F12 — Status ở reset/idle không phải transaction done

`mem_mapping.sv:178,244,259–260`: sau reset w_ptr=end=0 -> write_finish1 dù chưa có transaction. Register cũng full/empty1 vì end/pointer đều0 (`regfile.sv:81–93,216–227`). Nếu dùng như idle/ready level thì cần định nghĩa; top hazard hiện dùng như completion. Các reset_ptr sinh từ decode state thay vì trực tiếp rst_n (`mem_mapping.sv:125,149,194`; `regfile.sv:99–100,131–132,162`) cần xem xét recovery/removal khi synthesis. Chưa có bằng chứng metastability từ RTL simulation; không gọi đó là lỗi silicon đã xác nhận. Không yêu cầu tự ý reset toàn RAM vì PDF không quy định nội dung RAM sau reset.

### F16 — Burst length và underflow

`mem_burst.v:139,151,166,189,203,224` dùng input length sống và `length-1` với unsized32-bit1. Length0 tạo so sánh với0xffffffff; counter10-bit không bao giờ đạt. Test >1024 cycle cả READ và WRITE vẫn RUN. Nếu length0 là illegal phải reject/assert rõ, không để phát command vô hạn. Request length3 rồi đổi input về1 làm controller dừng phát command sau1. Giữ length ổn định đến finish sẽ tránh nhánh lỗi thứ hai, nhưng interface không ghi hợp đồng đó. Độ rộng10-bit chỉ biểu diễn1..1023 cho burst hữu ích; không thể mã hóa1024 bằng0 như hiện tại.

### F17 — Command/WDF handshake

`mem_burst.v:189–192,224–229`: `app_wdf_end` hạ theo command address cuối thay vì theo data beat cuối được accept. Test length1, command ready trước WDF ready: đến lúc `app_wdf_wren && app_wdf_rdy` high, END đã0. `wr_data_cnt` còn đếm `wr_burst_data_req`, không trực tiếp đếm WDF handshake; request-data latency phải được quy định. Đối chiếu [AMD UG586 User Interface](https://docs.amd.com/r/en-US/ug586_7Series_MIS/User-Interface) và [Command Path](https://docs.amd.com/r/en-US/ug586_7Series_MIS/Command-Path): command/data được accept bằng các cặp valid/ready riêng; END phải thuộc đúng data cuối. Cần scoreboard independent counts dưới backpressure. Không kết luận phần DDR của top đã hỏng vì **mem_burst không được instantiate trong matmulfree**.

### F18 — Address truncation

`mem_burst.v:56,120,127`: RHS `{addr,3'd0}` rộng ADDR_BITS+3 nhưng destination vẫn ADDR_BITS. Với ADDR_BITS6, request8 -> app_addr0. Với mặc định28, mất3 bit cao tương tự. Nếu request là BL8-word address, nó phải giới hạn ADDR_BITS-3 và kiểm base+len-1 không vượt miền; nếu request đã dùng địa chỉ app thì không được shift. Increment8 cũng cần ràng buộc với cấu hình memory/MIG thật, không suy ra từ DATA_WIDTH đơn thuần.

### F19 — Reset và calibration của adapter

`mem_burst.v:37` có ui_clk_sync_rst nhưng không dùng; chỉ rst vào hai always. Test UI reset trong READ pending vẫn state1,en1. Dòng111 freeze FSM khi calib0 nhưng giữ en/address cũ; nếu app_rdy vẫn1, cùng command có thể được accept lặp mà counter không tăng. Nếu integration bảo đảm rst luôn bao gồm UI reset và không có handshake khi calib0, có thể tránh; hiện không có integration chứng minh điều đó. Không nhầm reset active-high adapter với reset active-low core: hai polarity tự chúng hợp lệ.

### F20 — Init assets thiếu

`ins_mem.sv:9`, `mem_mapping.sv:22`, `sigmoid.sv:11`, `exp.sv:10`, `norm.sv:11` phụ thuộc tên file tương đối theo working directory. Workspace không chứa instruction.mem/norm.mif; mem_init.mem,exp_content.mif,sigContent.mif chỉ tồn tại trong bộ review với nội dung zero do script tạo. Chúng **không phải LUT/model/program của luận văn**. Thiếu program/LUT làm không thể xác nhận sigmoid/exp accuracy hoặc end-to-end token workload. Không dùng fixture zero để kết luận SIG đúng.

### F21 — Parameterization

- `matmulfree.sv`, pipeline regs, `ternary_mul.sv`, `acc_mul.sv`, addsub/mul/div/exp hard-code16/32/512 và pointer cụ thể; top không nhận parameter.
- `rowwise_op.sv` quảng bá DATA_WIDTH nhưng child MUL/DIV dùng array16-bit, SIG được instantiate #(16,16). Probe DATA_WIDTH8 **không load design**, 6 lỗi vsim-3906 ở array ports, 225 warnings. Không thể nối zero-extend ngầm rồi gọi là scaled design đúng signedness.
- `regfile.sv` ADDR_WIDTH chỉ đổi port; case chỉ0..7, không default. ADDR_WIDTH>3 gặp selector8 sẽ giữ decode cũ/latch. MEM_DEPTH<16*2^ADDR_WIDTH với ADDR_WIDTH<=3 có thể OOB. Pointer19-bit không theo depth.
- `mem_mapping.sv` fixed selector3-bit/stride1024/pointer19-bit; depth tối thiểu8192 để phủ hết địa chỉ hợp lệ khi request giữ ổn định. Depth lớn hơn2^19 không address hết. Chiều data nhỏ hơn làm packing matrix thay đổi nếu dùng như core thật.
- LUT tham số vẫn cần regenerate đúng input/output/scale; không chỉ đổi declarations. Guard `$clog2(1)` và các width zero khi parameterize.

### F24 — X optimism

`ctrl_unit.sv:23` dùng casex, nên instr opcode toànX match nhánh LDV đầu tiên, bật reg_wr_en/mem_rden0. Test tái hiện. Gặp ROM chưa init (F20), simulator có thể thực thi giả load thay vì phản ánh instruction không hợp lệ. Dùng case/casez chỉ với wildcard chủ ý và assert known opcode khi valid. Đây là robustness/verification bug, không phải mô hình transistor xử lý giá trị X.

## Bao phủ và giới hạn kiểm chứng

| File/module | Đã kiểm tra | Kết quả liên quan |
|---|---|---|
| addsub, mul, div, exp, rowwise_op | Đọc toàn bộ; directed RTL simulation | F01–06, F21 |
| sigmoid, norm | Toàn bộ lookup/index/init; đường tích hợp | F06,F20,F21; sign-bit offset trong sigmoid mặc định là phép mapping hợp lệ nếu LUT đúng thứ tự |
| acc_mul | Toàn bộ cây cộng; simulation overflow | F15; 9 mức cộng, không clock register |
| ternary_mul | Toàn bộ capture/index/compute/write logic; enumerate index | F13–15,F26; chưa elaborate/simulate toàn module |
| mem_mapping, register | FSM, end/flags/reset/decode; directed simulation | F07–12,F21 |
| ctrl_unit, hazard_detect | Toàn bộ decode/control; truth-table simulation | F22,F24 |
| PC, ins_mem | Width, wrap, reset polarity, ROM init | F20,F21,F23; PC wrap modulo512 là xác định, không tự coi là bug nếu program có HALT |
| fd_reg, de_reg, em_reg, mw_reg | Reset, enables, control/data alignment tại register | Không thấy thiếu reset riêng ở các register này; F21 về width và F22/F27 ở integration |
| matmulfree, matmul_wrap | Toàn bộ nối dây, lifecycle, snapshot, ready | F14,F22,F23,F25,F27; không có DDR connection |
| mem_burst | Toàn bộ FSM/counters; backpressure/length/reset probes | F16–19 |

ModelSim Intel FPGA Starter 2020.1:

1. `review/sim/run.ps1`: compile22 file, simulate tb_review, **17/17** điều kiện tái hiện; các nhãn ID có sẵn được giữ để truy log. F09 register là contract observation như đã giải thích.
2. `run_extended.ps1`: **20/20** điều kiện tái hiện; bản cuối có test pointer vượt8191 thật sự. `simulation-extended.log` ghi Time21476ns.
3. `tb_param_probe.sv`: expected elaboration failure, **6 error vsim-3906**, chứng minh F21.
4. `tb_scaled_profiles`: các consistency assertion của cấu hình đề xuất qua, `SCALED_PROFILE_VALID` trong scaled-profile.log. Đây chỉ là kiểm cấu hình, không phải top functional pass.
5. `static_evidence.py`: enumerate index packing, lưu static-evidence.json.
6. `tb_scaled_leaf.sv`: instantiate package profile A thật sự, kiểm write register selector3 tới word63, memory endpoint8191 và burst read2 beat; log `SCALED_LEAF_PASS`.

**37/37 là số điều kiện quan sát được tái hiện, không phải 37 lỗi độc lập hoặc 37 test thiết kế pass.** Tổng hợp27 nhóm finding, gồm lỗi chắc chắn và rủi ro phụ thuộc hợp đồng. Chưa chạy full matmulfree/TMATMUL workload, formal, synthesis, STA hay FPGA. Không xác nhận throughput/200MHz/tiết kiệm tài nguyên của PDF. Các lỗi static quan trọng vẫn có bằng chứng cụ thể, không được ghi nhầm thành simulation.

## Cấu hình scaled-down đã tạo

Xem [SCALED_CONFIG.md](SCALED_CONFIG.md) và [scaled_profiles.sv](scaled_profiles.sv). Profile A chạy trên leaf RTL gốc, đã được dùng trong test17/17. Profile B giữ ISA13-bit, 8 register, 32 lane, vector512 và ma trận512x512; giảm data xuống8-bit, physical pointer/depth và PC. Profile B đã kiểm quan hệ width/depth, **chưa áp vào core do F21**. Giảm data precision không thể bảo đảm bit-exact16-bit cho mọi input; giữ semantics/operator/dataflow, so sánh trong miền giá trị và precision của profile.

## Đề xuất patch sau review

Chi tiết nằm ở [PATCH_PROPOSAL.md](PATCH_PROPOSAL.md). Đây là đề xuất, **chưa áp patch**. Ưu tiên sửa đường TMATMUL và contract transaction, arithmetic/memory, rồi đưa parameter xuyên suốt; không dùng cấu hình nhỏ để che đi lỗi của cấu hình gốc.
