# Kiểm chứng llm_soc trên server

> **Category: GUIDE.**

[Flow server và cấu hình](../../tools/server/README.md) là hướng dẫn chạy hiện tại
trên branch `remote`. Chạy Xcelium/Genus trong allocation Slurm; các entry point
local ModelSim/Questa/Verilator/Quartus đã ngừng hoạt động.

| Mức kiểm chứng | Entry point từ repo root trên compute node | Phạm vi |
|---|---|---|
| Full regression | `python3 tools/server/run_flow.py --stage test --tag TAG` | 7 nhóm graph + linear stream + host cancel |
| Debug nhóm | `--stage test --only tb_llm_ram --tag TAG` | Selected groups, không full PASS |
| Synthesis | `--stage syn --lib /approved/cells.lib --tag TAG` | Genus mapped netlist, design/area/timing reports |
| Test + synthesis | `--stage all --lib /approved/cells.lib --tag TAG` | Hai claim được ghi riêng |
| Application | `--stage application --fixture PATH --tag TAG` | Functional checkpoint token matching |
| Legacy shared RTL | `--stage legacy --tag TAG` | 9 legacy tops bằng Xcelium |

Theo [runbook riêng](../../SERVER_ACCESS.md) trước kết nối; không commit/upload
runbook hoặc credential. Transfer và allocation cần authorization phù hợp.
Module Genus, Liberty và quyền transfer chưa được xác nhận cho migration này.
`--check-inputs` kiểm tra file/config/manifest, không phải simulator hay synthesis PASS.

Reports nằm ở `reports/TAG`, database ở `build/TAG`. Tags mới bắt buộc; runner
lưu node/job/commands/hashes/markers và từ chối input đổi giữa lượt chạy. Job dài
chỉ kiểm tra ban đầu một lần rồi bàn giao theo hướng dẫn server, không poll/relaunch.

Mặc định RAM portable; không compile vendor RAM leaf. Giữ nguyên numeric và
protocol assertions. Chuyển backend/tool cần full regression mới; FPGA timing,
unit PASS lịch sử và application PASS là các claim riêng, không tự chuyển sang
source mới. Genus completion không xác nhận timing closure hay ASIC signoff.

[Trạng thái/evidence trước migration](optimization_status.md) vẫn giữ nguyên.
Lệnh và diễn biến local cũ xem [lịch sử](../history/full_rtl_verification_development.md)
và lịch sử Git. Không chạy runner snapshot để thay source hiện tại.
