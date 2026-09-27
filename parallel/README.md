# TMATMUL chạy song song với ALU

RTL hiện tại cho phép các lệnh ALU dùng register (ADD/SUB/MUL/DIV/EXP/SIG)
tiến qua pipeline trong khi TMATMUL đang tính và ghi bộ nhớ. Engine TMATMUL
vẫn dùng 32 lane mặc định và xử lý từng hàng theo thời gian.

LDV, STV, TMATMUL tiếp theo và HALT được giữ ở **decode** khi TM đang bận,
bao gồm cả chu kỳ phát start. Điều kiện chờ không phụ thuộc `read_finish`:
đọc xong đầu vào chưa có nghĩa tính/ghi xong đầu ra. Lệnh TM mới còn chờ các
giao dịch register/memory trước đó thoát hết.

`decode_bubble` giữ PC và FD/DE, ngăn lệnh đang chờ bắt đầu đọc register,
đồng thời đưa NOP và các write-enable bằng 0 vào DE/EM. Các tầng EM/MW/WB
tiếp tục chạy để ghi đủ kết quả ALU đi trước. Không flush WB do lệnh memory
đang chờ. HALT không giữ write-enable của lệnh đi trước; `ready` tại top chỉ
lên khi các giao dịch đã hoàn tất.

Luồng vẫn in-order: không vượt qua một LDV/STV đang chờ để thực thi lệnh phía
sau nó. NORM vẫn dùng barrier riêng và chờ TM hoàn tất. Đường số học, memory
map và chính sách cờ/debug hiện có được giữ nguyên; đặc biệt `overflow_out`
vẫn ưu tiên cờ TM khi TM đang bận. Bộ test này xác nhận dữ liệu và lịch thực
thi, không bổ sung cơ chế lưu cờ riêng cho hai đơn vị chạy đồng thời.

## Chạy kiểm chứng

Từ thư mục repo:

```powershell
./parallel/run.ps1
```

Có thể truyền `-SimBin` và `-Python` để chọn ModelSim/Python. Chạy nhanh một
nhóm: `./parallel/run.ps1 -Cases 0,1,2 -SkipNormRegression`. Mỗi báo cáo
`verification.json` ghi chính xác các ca đã chạy và SHA-256 nguồn/asset.

| Case | Chương trình / điều kiện kiểm |
|---|---|
| 0 | TM → ADD → SUB phụ thuộc ADD → SIG phụ thuộc SUB → HALT |
| 1 | Như case 0, thêm LDV kết quả TM; kiểm không mất phần cuối SIG |
| 2 | Như case 0, thêm STV kết quả SIG |
| 3 | Hai TM liên tiếp, TM sau dùng kết quả TM trước, rồi ADD |
| 4 | TM → HALT ngay lập tức |
| 5 | STV → TM dùng dữ liệu vừa store → ADD → LDV |
| 6 | TM → ADD → LDV → SUB dùng kết quả load → STV |
| 7 | Reset khi TM và ALU đang chạy, khởi động lại case 0 |
| 8 | LDV → TM → ADD, kiểm TM không chiếm memory của load trước |
| 9 | TM → STV ngay lập tức, kiểm không đọc register quá sớm |
| 10 | TM → LDV ngay lập tức |
| 11 | Như case 1, chặn handshake đầu ra 40 clock sau `read_finish` |

Mỗi word thực sự ghi vào register được so với dữ liệu kỳ vọng, kiểm đúng
16 word/bank, không ghi lặp; mọi beat TM và các vùng memory đích cũng được
kiểm. Test đếm word ALU commit **trong lúc `tmatmul_assert=1`**, đồng thời ghi
chu kỳ đầu/cuối của overlap và chu kỳ TM đầu tiên hoàn tất. SIG dùng LUT thật
trong `Verilog Source code/sigContent.mif`; EXP không được thực thi trong
những ca này và dùng fixture zero để elaborate. Không khẳng định sửa độ chính
xác các phép toán MUL/DIV/EXP từ các test điều khiển này.

Runner còn chạy lại `tmatmul/sim/tb_core.sv` (ba TM liên tiếp/in-place),
`norm/tests/tb_norm_core.sv` với và không có TM, và `tb_norm_memory.sv`.
Fixtures NORM dùng oracle hiện có, xuất vào `parallel/sim/norm` để giữ các
báo cáo cũ. Không dùng stub thay cho core hoặc engine TM.

## Waveform

Mỗi ca lưu `parallel/sim/case-N.wlf`; `record.do` chọn các tín hiệu pipeline,
TM busy/done/read_finish, `decode_bubble`, con trỏ ghi register và dữ liệu WB.
Mở file bằng ModelSim, thêm các tín hiệu đã log vào cửa sổ Wave. Ở case 0,
quan sát `register_inst.state_write == 2` và `overlap_words` tăng khi
`tmatmul_assert == 1`. Ở case 11, LDV tiếp tục ở decode sau `read_finish` và
chỉ được nhả sau TM hoàn tất.

Đây là mô phỏng RTL; chưa đo timing/Fmax hoặc PPA sau synthesis cho thay đổi này.
