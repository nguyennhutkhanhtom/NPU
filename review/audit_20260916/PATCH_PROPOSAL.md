# Đề xuất patch sau review — chưa áp dụng

Mục tiêu là khôi phục semantics trong PDF và cho phép cấu hình nhỏ mà vẫn giữ ISA, pipeline5-stage, datapath32 lane, dual-read/single-write và TMATMUL. Không hợp nhất các thay đổi thành một rewrite lớn; mỗi nhóm phải có oracle/test đối chiếu riêng. Sửa functional bug tất nhiên thay đổi behavior sai của RTL hiện tại; bảo toàn behavior ở đây là behavior được đặc tả.

## 1. Chốt các hợp đồng còn thiếu trong tài liệu

Các quyết định này phải được ghi vào spec trước khi chọn implementation, không tự lấp bằng literal:

- Q4.12 cho toàn datapath16-bit hay định dạng khác? Target nhỏ đề xuất Q4.4. Chọn rounding và overflow policy; phân biệt signed overflow với unsigned carry/borrow.
- DIV zero/MIN/-1, EXP clamp/domain và thứ tự LUT, RMS epsilon/scale/gamma có hay không. NORM phải thực sự phụ thuộc cả vector.
- `w_en/rd_en` là request-start hay beat-valid? Đề xuất latch request ở IDLE và dùng một điều kiện accept-beat thống nhất để write/advance/count. Buffer/FSM hiện có được giữ, không dùng một tín hiệu với hai nghĩa khác nhau.
- Operand fields TMATMUL và memory map chuẩn: vùng ternary, activation, output; yêu cầu STORE rồi TMATMUL dùng đúng vector vừa STORE. Không chỉ tráo hai dây để che F25.
- Xác định `read_finish`, `result_valid`, `write_done`, `ready`. Busy phải bao trùm cả ghi đủ16 word. Nếu external ports giữ nguyên, vẫn cần phân biệt các điều kiện này ở nội bộ.

## 2. Arithmetic và status — F01–06,F15

- ADD/SUB: dùng `is_sub=(select==SUB)`; mở rộng a,b lên W+1 rõ ràng, XOR b với mask trước cộng carry-in. Kiểm5-3,5+3,MIN/MAX và carry/borrow; không chỉ sửa dấu ngoặc một chỗ.
- MUL: signed product2W-bit; arithmetic shift FRAC_W; kiểm sign-extension ở phần bị bỏ, rồi quantize theo policy. Scalar overflow nối scalar và chỉ chọn khi opcodeMUL.
- DIV: sign-extend numerator lên ít nhất W+FRAC_W trước shift; guard zero/MIN/-1, kiểm scale1/1=1 và số âm.
- EXP: mapping đúng số entry/domain, hoặc sinh bảng đủ miền. Không sửa index bằng truncate tùy tiện. SIG giữ mapping sign-bit hiện có nếu LUT cùng thứ tự; kiểm(sigmoid(0), âm/dương, monotonicity) với golden LUT.
- NORM: thay đường zero bằng tính RMS của512 phần tử theo PDF. LUT unary norm hiện có không đủ thông tin. Việc bổ sung datapath normalization còn thiếu là functional implementation, không phải parameter-only change; cần giữ pipeline interface và quản lý latency thật trong control.
- Ternary arithmetic: sign-extend trước negate; adder tree giữ guard bits; quantize một lần ở cuối. Không tự thêm clock stages vào cây đang combinational khi mục tiêu là giữ kiến trúc.
- Mux carry/overflow theo opcode, không OR flag của những unit không được chọn.

## 3. Memory transaction — F07–12

- Thay literal hỏng bằng biểu thức width-safe: `BANK_STRIDE=REG_COUNT*VECTOR_WORDS`; decode trong đủ width và assert address<depth.
- Latch base, end/count, mode và active-port mask lúc accept request. Almost flags dựa descriptor đã latch và latency; không dùng request mới khi busy.
- Dùng remaining-beat counter hoặc inclusive-last rõ ràng: word cuối phải được commit trước done. Giữ đúng16 write ở baseline; read last-valid không bị hiểu thành “đã đọc xong” sớm.
- RAM write, pointer increment và remaining decrement cùng dùng `write_accept`. Trong TMATMUL, chỉ write khi result_valid; trong stream register xác định nguồn luôn có data hay có bubble.
- Tách inactive/idle status khỏi transaction-done pulse hoặc mô tả rõ level semantics và cập nhật tất cả consumer.
- Reset FSM/pointer/valid theo cùng rst_n; loại reset sinh combinational từ state nếu không thật sự cần. Không thêm reset toàn RAM khi không có yêu cầu.

## 4. TMATMUL và pipeline integration — F13,F14,F22,F25–27,F23

- Index giải nén phải là `word_idx*TERNARY_PER_WORD+lane`; kiểm tất cả phần tử được drive đúng một lần và không index ngoài miền.
- Theo memory map chuẩn, nối matrix stream vào buffer ternary, activation stream vào buffer activation, với đúng source field. Test marker/identity và STORE->TMATMUL, không chỉ all-zero.
- Capture chỉ khi dữ liệu tương ứng valid; reset counters lúc accept transaction mới. Giữ activation ổn định sau đủ VECTOR_WORDS, tránh replay overwrite vô điều kiện.
- Latch context của TMATMUL duy nhất khi start; giữ operand/destination/mode/control khi busy và khi các stage khác tiếp tục chạy.
- Output đóng gói theo `result_word[lane*DATA_W +: DATA_W]`. Giữ result/control ổn định đến write_accept.
- Write counter chạy0..VECTOR_WORDS-1; top thoát RUN sau **last accepted output beat**, không phải khi write-enable vừa lên. Tách read_done khỏi transaction_done, tránh nhả hazard giữa read và write.
- Bảo vệ RAW/WAR/WAW và memory ownership theo producer/consumer thực tế. Có thể dùng scoreboard/busy per resource trong control hiện có; không thay datapath hoặc forward kết quả chưa valid. Kiểm back-to-back TMATMUL và TMATMUL->LDV/STV.
- Flush chỉ instruction bị squash, không xóa load hợp lệ đang đợi. HALT so opcode1111 và ready sau pipeline/stream drain xong, độc lập9 operand bit.
- Ctrl decode dùng exact case, invalid opcode không bật side effect; assertions chỉ kiểm instruction khi valid.

## 5. Adapter DDR riêng — F16–19

- Latch length/base khi request accepted; reject hoặc complete-no-op length0 theo contract. Counter width bao phủ hợp lệ và không so10-bit với unsigned underflow32-bit.
- Đếm command bằng `app_en&&app_rdy`, data bằng `app_wdf_wren&&app_wdf_rdy`; END thuộc data beat cuối, độc lập command counter.
- Quy định request-to-write-data latency và giữ data/end ổn định qua backpressure. Không đưa một request-data pulse vào vai trò accepted-data.
- Phân biệt burst-word address và app address bằng width/unit riêng; kiểm address+len. Không silently truncate3 bit.
- Kết hợp hoặc ràng buộc UI reset/calibration với reset adapter; không để enabled command lặp khi FSM freeze. Không nối adapter vào top như một phần của patch scale.

## 6. Parameter xuyên suốt — F21

- Thêm parameter tại top và propagate qua pipeline registers, ALU/children, register, mapper, TMATMUL, acc, PC/ROM/LUT. Dùng package config đã tạo làm đầu vào, không substitute chuỗi trên RTL.
- Giữ mặc định16-bit/32 lane/vector512/ISA13-bit để regression; instantiate target8-bit như SCALED_CONFIG.md.
- Dùng derived type/width: WORD_W, VECTOR_WORDS, MATRIX_WORDS, guard width, depth và pointer. `$clog2` có lower bound1; assert các phép chia packing, parameter>0, endpoint<depth.
- Các generic decode dùng phép nhân đủ width thay case0..7 nếu muốn hỗ trợ selector rộng hơn; với profile giữ8 register, không cần đổi encoding ISA.
- Không giữ fixed constants1024 khi WORD_W giảm256: matrix vẫn512x512 ternary nên cần2048 word.
- Rà lại write/read latency khi sửa functional bugs; không dùng almost_* offset12 như phép bù cứng cho mọi cấu hình.

## 7. Tiêu chí chấp nhận patch

1. Default và scaled đều elaborate không width/undriven/OOB warning quan trọng; không suppress để làm log sạch.
2. Arithmetic reference tests: zero,1,-1,MIN,MAX, fractional, overflow/underflow; exhaustive cho data width nhỏ khi khả thi.
3. Stream RAM: beat0/last, high selector, bubble/start protocol, input descriptor đổi lúc busy, reset giữa giao dịch. Scoreboard đếm chính xác read/write accept và so toàn vector.
4. TMATMUL: zero/identity/diagonal/mixed ternary, activation có lane marker; hai transaction liên tiếp; result_valid bị giữ; matrix/activation/output khác base và các trường hợp overlap được phép.
5. Pipeline chương trình LDV->ADD/SUB->STV, producer->consumer, NORM->STV->TMATMUL->LDV, HALT mọi operand bits, busy reset và missing-init fail rõ ràng.
6. DDR request lengths1/2/max/0, base gần biên, independent random command/data backpressure, UI reset. Scoreboard không mất/nhân đôi command/data.
7. Golden assets thật được version hóa; fixture zero không dùng làm bằng chứng numeric. So scaled theo quantization contract, không hứa bit-exact16-bit ngoài miền chung.
8. SHA/baseline được giữ; functional fixes và parameterization có diff riêng để review.

Chưa có patch nào được áp vào RTL trong đợt review này.
