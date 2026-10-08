# Full RTL tests trên server

> **Category: GUIDE.**

Chạy từ repo root trong Linux Slurm bằng `tools/server/run_flow.py`.
[Hướng dẫn chạy, cấu hình và evidence](../../tools/server/README.md).
Không dùng các runner PowerShell local; chúng trả lỗi hướng sang flow server.

| Testbench | Top | Phạm vi |
|---|---|---|
| tb_memory_ip.sv | tb_llm_memory | Portable memory, expected words độc lập, OLD_DATA, latency, tiles, reset |
| tb_math.sv | tb_llm_math | Arithmetic, lookup, ternary, normalization |
| tb_ram.sv | tb_llm_ram | Adapter latency, lane masks và reset cancellation |
| tb_protocol.sv | tb_llm_protocol | Host requests/writes/cancel/bounds |
| tb_selection.sv | tb_llm_selection | Excluded IDs, extrema và stable ties |
| tb_operators.sv | tb_llm_operators | Numeric operators và context/reset cases |
| tb_graph.sv | tb_llm_graph | Autonomous synthetic graph, causal/token/traffic assertions |
| tb_linear_stream.sv | tb_llm_linear_stream | Ordered rows, backpressure, faults và drain |
| host_cancel_contract.sv | tb_host_cancel_contract | Accepted portable SRAM commit trước ACK và cancel |

Default `--stage test` chạy cả 9 nhóm. `--only TOP ...` chỉ là selected PASS.
Runner truyền đường dẫn tuyệt đối của `sigmoid_257.mem` bằng `+SIGMOID_LUT=...`;
operator fixture từ chối LUT bị thiếu trước kiểm tra số học. Database riêng của
từng top không phụ thuộc working directory gốc của checkout.
Memory coverage của FPGA-IP equivalence trước đây được giữ trong evidence cũ;
flow hiện tại không kiểm chứng FPGA IP và không dùng library altera_mf.

Application exporter chạy trên compute node và ghi fixture mới qua `--output`;
runner `--stage application --fixture PATH` kiểm tra reference/input/RTL hashes,
host-loads config/parameters/prompt và so sánh output tokens. Expected IDs không
điều khiển DUT. Kết quả là functional token matching, không hardware/signoff gate.

Các scripts memory_model.py/check_gate.py/finalize_application.py còn giữ helpers
để đọc cấu trúc evidence cũ; entry points local đã bị chặn. Evidence cũ không
thay cho regression/synthesis của cấu hình portable mới.
