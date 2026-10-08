# Flow test và synthesis trên DOE Lab

Đây là hướng dẫn chạy hiện tại trên branch `remote`. EDA chạy trên Linux compute
node trong Slurm: **Xcelium (`xrun`) cho test, Genus cho synthesis**. Không dùng
Quartus, ModelSim, Questa hoặc Verilator local. File này là điểm đọc duy nhất cho
kết nối, SSH/X11, transfer, test và synthesis; `SERVER_ACCESS.md` đã được thay
bằng thông báo chuyển hướng.

## Kết nối và xác thực server

| Thiết lập | Giá trị |
|---|---|
| VPN | WireGuard tunnel `ee5303_09`, đã bật trên máy thực thi SSH |
| VPN config | `ee5303_09.conf`, chỉ lưu riêng ở local; không đọc/in/copy nội dung |
| SSH host / port | `red.doelab.site`, TCP `22` |
| Tài khoản Linux | `ee5303_09` |
| Compute nodes | `black`, `gray`, `white`, cấp qua Slurm |
| Task directory | `$HOME/project/test_khanh`, kiểm tra đường dẫn resolved/symlink trước khi ghi |
| Remote Desktop | Cùng host/tài khoản, màu 16-bit theo hướng dẫn lab; giữ phiên X11 hoạt động |

Người dùng bật VPN trên chính máy thực thi SSH; Codex không đọc VPN config hoặc
đổi VPN/DNS. Kết nối từ sandbox/cloud không được mặc định là có VPN. Từ terminal:

```powershell
ssh ee5303_09@red.doelab.site
```

Xác minh host key với nguồn tin cậy khi gặp host mới/mismatch; không tự chấp nhận
key lạ và không tắt host-key checking. Đổi mật khẩu lần đầu/MFA do người dùng
thực hiện ở prompt tin cậy; không đoán hoặc retry mật khẩu bị từ chối.

Mật khẩu không nằm trong Markdown. Dữ liệu xác thực local đã được tách vào
`tools/server/.local/credentials.json`, ignored bởi Git, ACL chỉ cho tài khoản
Windows hiện tại và SYSTEM. Không đọc/in mật khẩu, commit, upload hay đưa nó vào
command arguments, environment, transcript hoặc logs. File lưu thông tin
`host`, `user`, `password`; nếu cần cập nhật thì chỉ sửa riêng tại local, không
chép giá trị vào tài liệu. Có thể bỏ `-UseSavedPassword` và dùng prompt SSH thủ công.

Sau đợt gộp tài liệu, credential đã được chuyển và kiểm tra readback tại local;
kiểm tra cú pháp helper đạt. Lần thử SSH bằng credential này bị server từ chối
(`Permission denied`); chưa xác nhận lại login. Kiểm tra/cập nhật mật khẩu hiện
tại trực tiếp trong file local hoặc ở SSH prompt, không gửi giá trị vào chat.
Không retry tự động khi chưa có thông tin xác thực mới. Kết quả regression đã
ghi trước đó vẫn thuộc phiên/source được lưu trong evidence, không phải lần login này.

`ssh-auth.ps1` dùng Git for Windows SSH và temporary askpass helper: đọc JSON
trong bộ nhớ, chỉ trả mật khẩu vào đúng prompt của tài khoản/host trên. Không
chạy helper standalone; stdout chỉ được SSH tiêu thụ. Helper được xóa sau phiên,
environment chỉ được đặt cho process SSH. `DISPLAY=codex:0` của askpass là giá trị
local để bật helper, không phải display X11 trên server; X11 thật được xác thực
riêng bằng launcher bên dưới. Dùng `StrictHostKeyChecking=yes`, known_hosts của
người dùng, timeout 10 giây và tối đa một password prompt.

### Phạm vi thao tác

SSH login, kiểm tra chỉ đọc và chỉnh sửa liên quan task đã được người dùng cho
phép trong phiên làm việc; không cần hỏi lại cùng thao tác đã được cho phép.
Authorization chỉ áp dụng cho task hiện tại, không phải quyền làm việc khác.
Transfer, Slurm allocation và job dài cần authorization tương ứng; không tự đổi
VPN, cài phần mềm, đổi account/security hoặc commit/push nếu chưa được yêu cầu.

Remote writes giới hạn ở `.sv`, `.md` liên quan task và các file trong resolved
`$HOME/project/test_khanh`. Giữ work/evidence cũ; không xóa hoặc ghi đè phá hủy.
Không chạy compute nặng trên login node. Xác nhận connection, allocation,
module, tool và output từ kết quả thực tế; không coi tài liệu là EDA PASS.

SFTP/SCP mặc định bị lab hạn chế. Chỉ dùng phương thức admin đã cho phép; không
đổi giao thức hoặc tunnel để vượt hạn chế. Trong phiên migration này, người dùng
đã xác nhận quyền dùng scripts copy/download SSH. Khi gặp từ chối transfer,
dừng và liên hệ admin. Không nới quyền từ một hướng dẫn Markdown.

### Xử lý lỗi kết nối

| Lỗi | Kiểm tra tiếp |
|---|---|
| Không resolve/timeout | VPN trên cùng máy/network namespace; dùng escalation bình thường nếu sandbox không có network |
| Host key mismatch | Dừng để người dùng/admin xác minh, không disable checking |
| Authentication rejected | Kiểm tra credential hiện tại; không retry nếu chưa có thông tin mới |
| `module` không có trên login node | Cấp compute node trước; module đã được xác nhận trên black |
| X11 thiếu DISPLAY | Giữ `--x11`; dùng phiên RDP/X11 của chính tài khoản qua launcher bên dưới |
| Slurm thiếu tài nguyên | Kiểm tra availability/policy của black/gray/white, không tạo nhiều phiên hoặc request lặp |
| Transfer bị từ chối | Xác nhận quyền admin cho đúng phương thức, không tìm cách vượt chặn |

## Cấu hình cần sửa khi đổi môi trường

| File | Nội dung |
|---|---|
| `tools/server/flow.json` | Package order, excluded FPGA leaf, danh sách test/top/PASS marker và modules |
| `tools/server/asic.sdc` | Clock 10 ns và I/O budgets ban đầu; cần review theo integration thực tế |
| `tools/server/genus.tcl` | Read/elaborate/check/syn_generic/syn_map/syn_opt và xuất reports |
| `tools/server/run_flow.py` | Preflight, lựa chọn stage/top, log và hash provenance |

Đã xác nhận `cadence/xcelium/2409` và `cadence/genus/211` trên compute node `black`
trong Slurm job `64315`; các version nằm trong `flow.json`.
Liberty `.lib` phải do lab cung cấp, truyền `--lib` cho từng library; không đoán
module, technology/process corner hoặc cài phần mềm. Có thể tự load modules rồi
gọi Python trực tiếp; wrapper `run.sh` dùng cấu hình JSON.

## Chuẩn bị source và phiên làm việc

1. Bật VPN theo phần kết nối ở trên, dùng SSH với host key đã xác minh. Không đổi VPN/DNS.
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

Giữ `--x11` bắt buộc; không có fallback bỏ flag này. Phiên tối đa 5 giờ
theo hướng dẫn. Login node chỉ dùng thao tác nhẹ; runner kiểm tra Linux, job ID
và hostname thuộc node list, không tự cấp allocation.

### SSH có X11 từ phiên Remote Desktop của cùng tài khoản

SSH không bị cấm chạy `srun --x11`. Lỗi `No DISPLAY variable set` xảy ra khi SSH
chưa có display xác thực. Máy Windows hiện không có X server local; phiên RDP
Linux đang hoạt động của cùng tài khoản cung cấp display dùng được. Probe từ SSH
đã xác nhận `xdpyinfo` trên login node, allocation `64315` trên `black` và
`COMPUTE_X11_CONNECTION_OK` với display Slurm `localhost:98.0`.

Sau transfer được phép và authorization chạy job, từ terminal Windows:

```powershell
ssh -t ee5303_09@red.doelab.site 'bash -l "$HOME/project/test_khanh/bundle_TAG/tools/server/slurm_x11.sh" test --tag test_next'
```

`slurm_x11.sh` dùng `resolve_x11.py` kiểm tra DISPLAY hiện tại hoặc display của
process thuộc **chính UID**, xác thực bằng `xdpyinfo`, rồi chạy
`srun --pty --x11 --nodelist=black -c 2` với giới hạn 5 giờ. Script không ghi cứng
display, không in cookie, không sửa Xauthority, không dùng `xhost +`, không mở
port hay đổi sshd. Nó fail trước allocation nếu không có display hợp lệ.
`run.sh` và Python runner kiểm tra kết nối X11 một lần nữa trên compute node.

Nếu phiên RDP/X11 đã đóng, mở lại desktop của tài khoản rồi thử launcher. Cũng
có thể dùng SSH `-X` khi có X server local và forwarding hoạt động; không tự gán
DISPLAY giả. Theo [OpenSSH](https://man.openbsd.org/ssh.1) và
[Slurm srun](https://slurm.schedmd.com/srun.html), SSH forwarding và Slurm X11
là hai bước riêng. Login node hiện không có `module`; module chỉ được load sau
allocation trên compute node.

Trong terminal của Remote Desktop cũng dùng cùng launcher:

```bash
cd "$HOME/project/test_khanh/bundle_TAG"
bash -l tools/server/slurm_x11.sh test --tag gui_test_next
```

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
./tools/server/copy-via-ssh.ps1 -AdminApprovedTransfer -SourcePath tests/full_rtl/build/bundle_TAG -TargetPath '~/project/test_khanh/bundle_TAG' -UseSavedPassword
```

Script chỉ nhận thư mục task dưới `~/project/test_khanh`, giữ file giống hash,
từ chối file khác hash/symlink và bảo vệ credentials/VPN config. Password được SSH
askpass đọc trong bộ nhớ; không truyền trong command arguments hoặc bundle.

## Trạng thái migration

Branch `remote` đã push commit source `f8983f4`. Sau khi người dùng xác nhận admin
cho phép transfer, script copy đã xác nhận 59 file (58 inputs + manifest), zero
errors, tại `/home/yellow/ee5303_09/project/test_khanh/server_migration_f8983f4`.
Server preflight: `FLOW_INPUTS_VERIFIED files=58`. Cú pháp Python/Bash, file
list/config và bundle hashes đã được kiểm tra; chưa phải EDA PASS.

Lỗi ban đầu do SSH thiếu DISPLAY đã được giải quyết bằng X11 của phiên RDP
thuộc tài khoản. Slurm probe `64315` xác nhận X11 trên `black` và modules EDA;
Allocation probe đã kết thúc. Mọi lượt mới giữ `--x11`; full regression PASS
được ghi bên dưới. Liberty library vẫn cần xác nhận trước mapped synthesis.

Launcher cũng cấp thành công job `64316`. Runner dừng trước EDA vì Python 3.6
trên compute không hỗ trợ keyword `subprocess(..., text=True)`; đã đổi sang
`universal_newlines=True`. Launcher/full-graph stdlib flow tương thích Python 3.6; legacy reference cần
Python 3.8+ (`math.isqrt`), checkpoint cần Python/dependencies do lab cung cấp.

Scoped job `64318` PASS hai nhóm memory (464 checks) và host cancel (14 checks)
qua SSH/X11, zero simulator diagnostics. Evidence đã download và xác minh mọi
report/frozen input SHA256 tại
[`server_x11_20261008_verified`](../../tests/full_rtl/evidence/server_x11_20261008_verified/x11_scoped3_20261008/results.json).
Xcelium NODNTW được sửa bằng input net type rõ ràng trong `postscale.sv`, không
waive warnings và không đổi arithmetic.

Full job `64319` pass memory/math/RAM/protocol/selection rồi dừng ở operators:
fixture dùng đường dẫn LUT tương đối không tồn tại trong database riêng
(`RMEMNOF`). Runner hiện truyền `+SIGMOID_LUT=` tuyệt đối; fixture fail sớm khi
file thiếu, giữ nguyên expected arithmetic.

**Full regression PASS:** job `64320`, `x11_full2_20261008`, trên black qua
SSH/X11 đã kết thúc và giải phóng allocation. Đủ 9 nhóm, zero simulator
diagnostics, `FLOW_COMPLETED` và `FULL_SERVER_REGRESSION_PASS`. Đã download và
verify mọi report/frozen input SHA256, cùng current RTL/tests/runtime scripts:
[`full server evidence`](../../tests/full_rtl/evidence/server_x11_full_20261008/x11_full2_20261008/results.json).
Reports server còn nguyên tại
`/home/yellow/ee5303_09/project/test_khanh/server_x11_lut_20261008/reports/x11_full2_20261008`.
Không relaunch lượt đã hoàn tất. Synthesis chưa chạy; cần Liberty library được
xác nhận. Legacy/application là gates riêng, chưa được kiểm chứng trong lượt này.

Download riêng reports của tag được phép:

```powershell
./tools/server/get-reports.ps1 -AdminApprovedTransfer -RemoteRoot '~/project/test_khanh/server_x11_lut_20261008' -Tag x11_full2_20261008 -UseSavedPassword
```
