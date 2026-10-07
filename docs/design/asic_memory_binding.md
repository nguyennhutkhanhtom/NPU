# Liên kết SRAM khi chuyển sang ASIC

> **Category: GUIDE.**

[Tài liệu](../README.md) · [Chính sách RTL portable](asic_portability.md) · [Toàn graph](full_rtl_language.md) · [Kiểm tra bộ nhớ](../../tests/full_rtl/tb_memory_ip.sv)

Khối compute/control vẫn dùng SystemVerilog có thể tổng hợp. Technology leaf
hiện tại là `quartus_word_ram`, được truy cập qua `pipelined_word_ram`; chỉ source
này instantiate trực tiếp `altsyncram`. Khi triển khai ASIC, cần cung cấp bản thay
thế dành riêng cho technology nhưng giữ cùng public leaf interface, rồi chọn source
đó trong ASIC file list. Giữ nguyên adapter branch và các client interface hiện có.
Tên `USE_QUARTUS_MEMORY` hiện chọn leaf branch này; nó không yêu cầu logic số học
hoặc điều khiển của Quartus.

Core chỉ có một `clk`. Các signal request/data của host phải đáp ứng contract
setup/hold của clock này và giữ ổn định trong suốt handshake. RTL không cung cấp
host clock độc lập hoặc cầu nối data CDC. Khi tích hợp ASIC với host thuộc clock
domain khác, phải bổ sung cầu nối đó ở upstream; hai reset-release FF chỉ đồng bộ
thời điểm deassert reset, không đồng bộ dữ liệu host.

Nhánh portable (`USE_QUARTUS_MEMORY=0`) dùng các mảng `sram_word_tile` được infer.
Vendor-free elaboration chỉ kiểm tra tính độc lập với vendor model; kết quả này
không chứng minh implementation/signoff ASIC. Xem [trạng thái kiểm chứng](../verification/optimization_status.md).

## Leaf contract và client

Leaf có một rising-edge clock dùng chung, một read port và một write port, địa chỉ
riêng biệt và whole-word write enable. Khi read được enable, địa chỉ được lấy mẫu
tại rising edge và word tương ứng xuất hiện sau edge đó. Khi read bị disable,
kết quả gần nhất được giữ nguyên. Write được enable sẽ commit tại edge đó. Nếu
read/write đồng thời trên cùng địa chỉ, read trả về word cũ. Leaf không có reset
port; nội dung/output khi power-up không được xác định. Client và test không được
đọc memory chưa khởi tạo. Reset điều khiển adapter hủy các enable đang chờ và
valid response, nhưng giữ dữ liệu đã commit; payload register không được reset.

| Full-top client | Leaf instances and geometry | Adapter contract |
|---|---|---|
| Parameter SRAM | 8 × 32 bits × 24576 rows | Compute read 5 edges; host read lane selection thêm 1 edge trước controller response. Write ACK theo actual leaf commit. |
| KV cache | 32 × 24 bits × 4096 rows | Read 5 edges; lane-masked write commit tại edge 4; busy bao phủ pending write. |
| Vector workspace | 32 × 24 bits × 96 rows | Read 5 edges; lane-masked write commit tại edge 4; dùng cùng reset/collision contract. |

Latency tính edge tiếp nhận là edge 1. Word adapter dùng read 3 edges khi có
<=4096 rows và 4 edges trong trường hợp còn lại; write commit tại edge 2. Các
stage request group/lane tạo nên latency của bank adapter nêu trên. Throughput
và collision behavior được kiểm tra bằng expected data độc lập cùng Quartus model
thực tế trong [trạng thái kiểm chứng hiện tại](../verification/optimization_status.md).
Khi thay đổi macro port, read latency hoặc collision semantics, phải điều chỉnh
boundary này và chạy lại các kiểm tra tương ứng. Collision response không xác định
không thể được xem là tương đương OLD_DATA. Việc chọn macro phải tính đến quy tắc
này và accepted request rate của adapter.

## Các mảng nhỏ do graph controller sở hữu

`llm_soc` còn chứa bốn mảng 128 entry với thao tác read/write hiển thị rõ trong
các FSM host/graph/operator. Đây là các mảng RTL được infer thông thường, không
instantiate vendor trực tiếp. Chúng có thể giữ dạng register/mux trong implementation
ASIC standard-cell. Nếu chuyển sang SRAM, phải bảo toàn cách lấy mẫu read và các
FSM stage hiện có; thêm một read edge chưa được tính đến sẽ làm thay đổi hành vi graph.

| Array | Logical payload | Source ownership and initialization |
|---|---:|---|
| prompt_memory | 128 × 12 bits = 192 bytes | Host ghi prompt ID trước khi launch; graph đọc các ID này trong prefill. |
| output_memory | 128 × 12 bits = 192 bytes | Graph ghi token đã chọn; host đọc các ID trả về. |
| score_memory | 128 × S32 = 512 bytes | Operator ghi causal score từ 0..position trước khi exponentiation đọc chúng. |
| probability_memory | 128 × U25 = 400 bytes | Operator ghi exponent weight từ 0..position trước khi value reduction đọc chúng. |

Các mảng này không được reset; ownership của count/state xác định entry nào hợp lệ.
[Fanout1 fitter report](../verification/timing/fullrtl100_fanout1/llm_soc.fit.rpt)
ánh xạ 1536 bits của output_memory và 3200 bits của probability_memory vào hai RAM
block bổ sung. 72 leaf instance trực tiếp chiếm 9510912 logical bits; cộng thêm
4736 inferred bits cho ra 9515648 block-memory bits như báo cáo. Các mảng prompt/score
dùng logic resource trong lần fit này. ASIC mapping không cần sao chép cách packing
đó. Forwarding logic report276020 của output RAM được infer bảo toàn read-during-write
semantics trong source; đây không phải một datapath IP instance riêng.

## EDA input khi có foundry target

Sử dụng cùng source compute/control, package và combinational LUT include của
`llm_soc` trong [source guide](../source_guide/blocks/README.md). Thay source của
memory technology leaf và cung cấp các view behavioral/Liberty/LEF của SRAM đã
chọn cùng standard-cell library. Giữ nguyên contract numeric/reset/handshake và
chạy lại các test unit, collision, cancellation và autonomous graph với leaf đó.
Dùng constraint synthesis/STA ASIC cho clock thực tế, môi trường I/O và library
corner; hoàn tất DFT và physical signoff bằng các technology tương ứng. Các
assignment device, pin, fanout và delay trong Quartus QSF chỉ thuộc demonstration
backend. Công việc này không bao gồm tích hợp board.
