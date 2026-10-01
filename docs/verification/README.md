# Kiểm chứng RTL, synthesis và timing

[Project](../../README.md) → [Tài liệu](../README.md) → **Kiểm chứng**

Full top `llm_soc` có [sáu nhóm unit](../../tests/full_rtl/README.md) và
[timing bốn corners riêng](timing/README.md). Timing đã đo70,41/83,58/84,49 MHz,
đều FAIL; local1 fit và sáu nhóm units PASS. Application pretrained chỉ chạy
khi exact source/config đạt >=100 MHz và units PASS. Các số liệu legacy
bên dưới thuộc `matmulfree`, không phải gate cho `llm_soc`.

Reference số nguyên và testbench kiểm tra chức năng, số học và giao tiếp của core. Demo Quartus kiểm tra Analysis & Synthesis và timing sau placement/routing trên cùng RTL; không có nhánh `SYNTHESIS`/`QUARTUS_SYNTHESIS`, primitive FPGA hoặc thuộc tính `ramstyle`/`M10K`. Binding SRAM và mục tiêu PPA ASIC được đánh giá riêng.

**[Timing post-fit: baseline, constraint, critical path và tối ưu Fmax](timing/README.md).** Report người dùng được giữ nguyên ở snapshot riêng; phép so sánh RTL dùng baseline với SDC và cấu hình compile tương ứng.

## Regression chức năng

Chạy từ thư mục gốc repository:

```powershell
./tests/run.ps1 -Block All
```

[Hướng dẫn test](../../tests/README.md) ghi cách chuẩn bị ModelSim, chọn từng khối và đọc logs/results. [Reference số nguyên](../../tests/reference.py) và [testbench](../../tests/tb_all.sv) dùng cùng RTL hiện hành, không có mode synthesis riêng.

| Phạm vi | Bằng chứng của bản ngày 01/10/2026 |
|---|---|
| Tổng regression | 10 mục PASS lúc 14:31:18, compile 0 error/0 warning |
| Tích hợp host và scheduler | 168 ca + 30 protocol reads/11 cancellations/4 blocked regions; gồm rejected NORM sau overflow, q alias và restart không reset |
| Rowwise registered datapath | 1.800 ca / 13.260 phần tử; 42.843 thay đổi input khi busy; reset sáu pha; reference S128 |
| Số học scalar | 4.301 sqrt, 37.189 RNE, 900 compose cases, 5 divider profiles |
| Postscale và sigmoid | 12.720 postscale checks; 1.638.400 input ở đủ 25 F_t |
| Memory và vector | 1.027 instruction checks, 47 SRAM checks, add/sub/mul và accumulator profiles |

[Design review](../reviews/design_review.md#kiểm-chứng-bản-rtl-thống-nhất) giải thích test coverage và cải tiến được kiểm tra. [Model demo](../demos/README.md) kiểm chứng thêm graph/checkpoint thực; kết quả model được ghi trong từng báo cáo riêng.

## Analysis & Synthesis hiện hành

Lượt Ctrl+K tương đương `quartus_map` hoàn tất **14:31:44 ngày 01/10/2026**, **0 error / 0 warning**, cùng RTL đã pass regression và hai model demo. Map ghi **7.390 registers**, **11.906 ALUT**, **8.174 ALM ước tính**, **334.336 bit RAM / 7 DSP**. ALM ước tính này chưa phải số sau placement/routing. [Timing hub](timing/README.md) gắn kết quả map, Fitter và STA với source/configuration hashes.

## Snapshot Analysis & Synthesis trước tối ưu timing

Ngày **01/10/2026**, project `matmul_free`, top `matmulfree`, Quartus Lite 18.1, Cyclone V `5CGXFC7C7F23C8`.

- Analysis & Synthesis (`quartus_map`, cùng bước Ctrl+K) thành công lúc **11:24:04: 0 error, 0 warning**.
- Không define macro để chọn nhánh RTL; project giữ effort AUTO và tối ưu AREA.
- Regression của snapshot trước tối ưu timing pass **9 mục kiểm tra** lúc 11:23:43, compile 0 error/0 warning. Chi tiết trong [báo cáo rà soát](../reviews/design_review.md); [manifest synthesis lịch sử](reports/synthesis.json) giữ hash RTL của snapshot này. `tests/results.json` được cập nhật cho regression hiện hành.

| Chỉ số trong demo FPGA | RTL thống nhất |
|---|---:|
| Dedicated logic registers | 6.497 |
| Block memory bits | 334.336 |
| Combinational ALUTs | 11.798 |
| Logic cells sau synthesis | 17.369 |
| Estimate ALMs needed | 8.005 |
| DSP blocks | 7 |

Report: [synthesis](reports/quartus_synthesis.rpt), [summary](reports/quartus_synthesis.summary). So với bản thống nhất lúc 01:51, giảm 215 FF, 508 ALUT và 766 logic cells; RAM/DSP giữ nguyên. ALM là estimate sau synthesis. Report A&S này không xác nhận Fmax; số liệu sau Fitter/Timing Analyzer được ghi trong [timing hub](timing/README.md). Mapping FPGA không xác nhận PPA ASIC.

[Manifest synthesis](reports/synthesis.json) ghi thời điểm, 31 source hashes, resource counts và checksum của report raw/archive. Dùng manifest cùng [results regression](../../tests/results.json) để đối chiếu đúng snapshot, thay vì dựa vào tên file report.

### Chạy lại A&S

Mở [project Quartus](../../quartus/matmul_free.qpf), chọn Analysis & Synthesis hoặc nhấn Ctrl+K. Có thể chạy bằng CLI khi `quartus_map` đã có trong PATH:

```powershell
Push-Location quartus
try {
    quartus_map matmul_free --read_settings_files=on --write_settings_files=off
} finally {
    Pop-Location
}
```

## Cách viết RTL đã giữ

1. Descriptor dùng index hằng và FF 32 bit thay ghi slice packed struct với dynamic index, reset đầy đủ.
2. SRAM dùng tám bank 32 bit, whole-word write/enable từng lane và synchronous read. RAM/read data không async reset; host valid so khớp request/response row/lane.
3. Package function gán đủ biến trên mọi path. RNE dùng thương signed-floor và phần dư, giữ ties-to-even.
4. Sized casts và shift amount rõ độ rộng; PC clear synchronous tách khỏi reset asynchronous.
5. NORM dùng chung hai multiplier/RNE giữa ba pass; ternary weight address dùng pointer và bounds shift/add.
6. Instruction RAM dùng một cổng synchronous chung và tag/valid. Scheduler chờ `instr_fetch_valid`; host chờ ready.
7. Sigmoid luôn dùng ROM hằng; coordinate S45/slope U10/product U34 có bound được kiểm tra bởi reference/testbench.
8. Sqrt dùng một subtractor U35; NORM divider U55; compose divider U48/U25 và strict RNE fit filter; rowwise gom scale/RNE.
9. Scale metadata 336 payload bits không reset, valid reset và gate mọi consumer; generate tường minh, genvar khai báo trước vòng lặp và index hằng mô tả tám bank FF với parallel reads.

Đây là các quy tắc coding style và hợp đồng bộ nhớ chung. Không thêm logic chọn implementation riêng của Quartus và không suppress warning để đạt kết quả.

## Lịch sử xử lý warnings

| Chỉ số demo | Trước sửa SRAM/descriptor | Sau sửa 30/09 | Sau tối ưu 01/10, trước bỏ macro |
|---|---:|---:|---:|
| Warnings | 174 | 1 | 0 |
| Dedicated logic registers | 339.651 | 13.393 | 6.712 |
| Block memory bits | 6.656 | 334.336 | 334.336 |
| Logic cells sau synthesis | 473.104 | 29.809 | 18.135 |
| Estimate ALMs needed | 230.916 | 12.814 | 8.441 |
| DSP blocks | 11 | 13 | 7 |

Warning 276020 read-during-write/pass-through của instruction memory đã hết sau khi thống nhất cổng đọc synchronous và tag/valid. Các lượt kiểm tra cấu trúc riêng cũ dùng FAST/một CPU có warning 12473 và 286029 do cấu hình tool; không phải lỗi chức năng RTL. Lượt sandbox cũ bị lỗi mở named pipe QSYN và đã chạy lại thành công với quyền mở pipe, giữ nguyên mức tối ưu.

Trong lượt rà soát này, dynamic-index write cho cache scale không reset làm Quartus suy luận hai RAM nhỏ và báo 276020 (thêm pass-through để giữ read-during-write). Đã đổi sang enable riêng với index hằng cho mỗi slot để mô tả FF có parallel reads; lượt cuối không còn warning và RAM bits trở lại 334.336. Không dùng ramstyle/primitive hay suppress warning. Quartus 18.1 cần generate/endgenerate và genvar khai báo riêng; đây vẫn là cùng RTL SystemVerilog cho mô phỏng và synthesis.

Các kết quả lịch sử không thay thế report và regression của snapshot hiện hành. Chi tiết thay đổi/latency: [rà soát design](../reviews/design_review.md).

---

[Đọc tiếp: model demo](../demos/README.md) · [Cải tiến design](../reviews/design_review.md) · [Về mục lục tài liệu](../README.md)
