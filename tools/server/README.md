# Flow test và synthesis trên DOE Lab

Đây là hướng dẫn chạy hiện tại trên branch `remote`. EDA chạy trên Linux compute
node trong Slurm: **Xcelium (`xrun`) cho test, Genus cho synthesis**. Không dùng
Quartus, ModelSim, Questa hoặc Verilator local. Đọc `SERVER_ACCESS.md` riêng trên
máy người dùng trước khi kết nối; file này chứa secret và không được đưa lên Git/server.

## Cấu hình cần sửa khi đổi môi trường

| File | Nội dung |
|---|---|
| `tools/server/flow.json` | Package order, excluded FPGA leaf, danh sách test/top/PASS marker và modules |
| `tools/server/asic.sdc` | Clock 10 ns và I/O budgets ban đầu; cần review theo integration thực tế |
| `tools/server/genus.tcl` | Read/elaborate/check/syn_generic/syn_map/syn_opt và xuất reports |
| `tools/server/run_flow.py` | Preflight, lựa chọn stage/top, log và hash provenance |

Module `cadence/xcelium/2409` lấy từ hướng dẫn lab, chưa xác nhận trên compute
node cho migration này. `modules.synthesis` để `null` cho đến khi xác nhận Genus.
Liberty `.lib` phải do lab cung cấp, truyền `--lib` cho từng library; không đoán
module, technology/process corner hoặc cài phần mềm. Có thể tự load modules rồi
gọi Python trực tiếp; wrapper `run.sh` dùng cấu hình JSON.

## Chuẩn bị source và phiên làm việc

1. Bật VPN theo runbook, dùng SSH với host key đã xác minh. Không đổi VPN/DNS.
2. Chỉ truyền file bằng phương thức được admin cho phép. SFTP/SCP bị chặn mặc định;
   không dùng stream SSH/base64/tar, Git clone hay giao thức khác để vượt hạn chế.
   Bản GitHub là deliverable; việc lấy source lên server cũng phải theo chính sách lab.
3. Dùng thư mục mới trong `$HOME/project/test_khanh`, kiểm tra `realpath` và symlink,
   giữ nguyên source/evidence cũ. Không upload toàn repo kèm secret, cache hay logs.
4. Sau khi người dùng phê duyệt allocation, lệnh theo hướng dẫn lab:

```bash
srun --pty --x11 --nodelist=black -c 2 bash
hostname
echo "$SLURM_JOB_ID"
module avail
```

Chỉ đổi node hoặc bỏ `--x11` sau khi xác nhận chính sách lab. Phiên tối đa 5 giờ
theo hướng dẫn. Login node chỉ dùng thao tác nhẹ; runner kiểm tra Linux, job ID
và hostname thuộc node list, không tự cấp allocation.

Trong thư mục source trên compute node:

```bash
python3 tools/server/run_flow.py --check-inputs
module load cadence/xcelium/2409
command -v xrun
python3 tools/server/run_flow.py --stage test --tag test_20261008
python3 tools/server/run_flow.py --stage test --only tb_llm_memory tb_host_cancel_contract --tag ram_debug_20261008
```

Full test gồm 7 nhóm memory/math/RAM/protocol/selection/operators/graph, cộng
linear stream và host cancel. Giữ numeric, collision OLD_DATA, latency, tile,
reset/cancel và traffic assertions. Memory test kiểm tra backend portable với
expected words độc lập; không còn kiểm chứng tương đương với FPGA IP. `--only`
chỉ ghi `SELECTED_GROUPS_PASS`; default ghi `FULL_SERVER_REGRESSION_PASS` sau
toàn bộ 9 nhóm. Testbench có force/deposit chạy với `-access +rwc`; warning/error
hoặc thiếu đúng marker đều làm fail, không waive diagnostics tự động.

Regression core legacy được giữ riêng: `python3 tools/server/run_flow.py
--stage legacy --tag legacy_next` chạy 9 top cũ bằng Xcelium; Python reference
sinh vectors trong từng database riêng, không ghi đè fixtures cũ. Chỉ chạy khi
thay đổi shared RTL hoặc cần kiểm tra legacy; `all` là full graph test + synthesis.

Sau khi xác nhận/load module Genus và Liberty library, chạy:

```bash
command -v genus
python3 tools/server/run_flow.py --stage syn --tag syn_20261008 --lib /approved/path/cells.lib
python3 tools/server/run_flow.py --stage all --tag all_20261008 --lib /approved/path/cells.lib
# Hoặc sau khi cập nhật modules trong flow.json:
bash -l tools/server/run.sh test --tag test_next
```

## Application checkpoint

Giữ pinned checkpoint/tokenizer và dependencies trong môi trường Python Linux
được lab cung cấp (`tests/language_demo/requirements.txt`); không copy Windows
packages và không tự cài dependency trên server. Chuẩn bị fixtures trên compute node:

```bash
python3 tests/full_rtl/export_checkpoint.py --output tests/full_rtl/build/fixture_next --prompt 'Once upon a time' --new-tokens 4 --min-new 4 --temperature 0 --seed 7
python3 tools/server/run_flow.py --stage application --fixture tests/full_rtl/build/fixture_next --tag application_next
```

Exporter từ chối thư mục đã tồn tại. Fixture gồm parameter/prompt/expected/config
và reference metadata; expected IDs không điều khiển DUT. Application stage là
functional token matching, không tự tuyên bố FPGA hardware gate/ASIC timing PASS.
Chạy full regression riêng trước khi chấp nhận một thay đổi dùng chung.

## Evidence, synthesis và job dài

`reports/TAG/results.json` ghi RUNNING/FAIL/COMPLETED, stage, job ID, node,
commands, input/library/SDC/fixture/report SHA256 và marker từng test. Mỗi top có
console/tool log và file list; `build/TAG` giữ database riêng. Tag đã tồn tại bị
từ chối. Không sửa input trong lúc job đo nó.

Genus xuất `llm_soc.v`, `llm_soc.sdc`, `area.rpt`, `timing.rpt`,
`check_design.rpt` và console log. `GENUS_FLOW_COMPLETED` chỉ xác nhận flow sinh
đủ reports/netlist; phải review unresolved design, mapping, timing và constraints.
RAM hiện là inferred portable RTL, chưa bind SRAM macro. Không suy ra ASIC
physical STA/PPA/DFT/CDC/signoff hoặc Fmax FPGA từ kết quả này. Evidence cũ giữ
nguyên, không dùng để chứng nhận source/configuration mới.

Khi job dài chưa xong, kiểm tra ban đầu tối đa một lần rồi bàn giao:

```bash
squeue -j "$SLURM_JOB_ID" -o '%.18i %.9T %.20N %.10M'
tail -n 15 reports/TAG/tb_llm_graph.console.log
cat reports/TAG/results.json
```

Ghi tag, job ID, node, PID (`echo $!` nếu tự chạy background), stage và đường
dẫn log chính xác. Completion là `FLOW_COMPLETED` cùng status `COMPLETED`; kiểm
tra marker/report/hash trước khi tiếp tục. Không launch lại job đang chạy,
không poll liên tục. Thoát compute shell rồi SSH khi hoàn tất.

Bundle tùy chọn cho transfer được phép: `prepare_bundle.py --output
tests/full_rtl/build/bundle_TAG` (thêm `--application` để lấy fixtures đã chuẩn
bị trong `tests/full_rtl/build`). Bundle loại secret/vendor model/evidence và
không truyền file. Chạy source trực tiếp từ checkout cũng được.

Sau khi admin cho phép phương thức SSH của script, copy từ PowerShell:

```powershell
./tools/server/copy-via-ssh.ps1 -AdminApprovedTransfer -SourcePath tests/full_rtl/build/bundle_TAG -TargetPath '~/project/test_khanh/bundle_TAG' -UseRunbookPassword
```

Script chỉ nhận thư mục task dưới `~/project/test_khanh`, giữ file giống hash,
từ chối file khác hash/symlink và bảo vệ runbook/VPN config. Password được SSH
askpass đọc trong bộ nhớ; không truyền trong command arguments hoặc bundle.

## Trạng thái migration

Branch `remote` đã push commit source `f8983f4`. Sau khi người dùng xác nhận admin
cho phép transfer, script copy đã xác nhận 59 file (58 inputs + manifest), zero
errors, tại `/home/yellow/ee5303_09/project/test_khanh/server_migration_f8983f4`.
Server preflight: `FLOW_INPUTS_VERIFIED files=58`. Cú pháp Python/Bash, file
list/config và bundle hashes đã được kiểm tra; chưa phải EDA PASS.

Shell login không có `module` hoặc `DISPLAY`. Lệnh Slurm có `--x11` bị từ chối:
`No DISPLAY variable set, cannot setup x11 forwarding`. Chưa có allocation/job
EDA. Tiếp tục sau khi X11 hoạt động hoặc lab xác nhận cho phép CLI bỏ `--x11`,
rồi khám phá module compute và Liberty library. Không tự bỏ `--x11` để thử lại.
