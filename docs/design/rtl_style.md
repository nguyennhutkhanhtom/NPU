# Chính sách RTL có thể tổng hợp

> **Category: POLICY.** Giữ cấu trúc phần cứng, timing boundary và register ownership tường minh.

## Tổng quan

| Phạm vi | Quy tắc |
|---|---|
| Sequential logic | One clear owner per register/array element; no multiple drivers or unintended latches |
| FSMs | Explicit state transitions, clock enables, pipeline registers and handshakes |
| Replication | `generate` for module/interface replication and independently owned lane registers |
| Procedural loops | Statically determinable bounds; review the resulting combinational depth and replicated hardware |
| Helpers | Small pure combinational or elaboration functions only |
| Memory | Technology macros confined to leaves behind explicit portable contracts |

## State và control

- Giữ FSM transition, register update, memory request và response capture hiển thị rõ trong RTL.
- Không dùng synthesizable task hoặc helper abstraction che khuất datapath, state, timing hay transaction quan trọng.
- Ưu tiên register/lane ownership tường minh. Có thể dùng procedural loop có giới hạn khi cấu trúc phần cứng tạo ra vẫn rõ ràng.
- Dùng clock enable. Không dùng logic tổ hợp để gate clock; technology clock gating thuộc integration boundary.
- Không dùng simulation delay, force/release, file I/O hoặc hành vi system-task trong RTL compute/control.

## Arithmetic

Thể hiện tường minh width, signedness, fixed-point scale, extension, truncation,
rounding và saturation. Dùng toán tử có thể tổng hợp thông thường khi chúng mô tả
rõ cấu trúc phần cứng mong muốn.

Giữ nguyên chủ đích tránh multiplier/divider: không thay datapath cấu trúc của NPU
bằng `*`, `/` tại runtime hoặc vendor arithmetic IP nếu chưa có thay đổi kiến trúc
được phê duyệt rõ ràng và verification về số học/PPA. Cho phép phép toán geometry/index
hằng số tại elaboration.

Giữ các helper thuần túy về saturation, rounding, extension và constant geometry
ở quy mô nhỏ. Arithmetic pipeline quan trọng phải nằm trong module tường minh.

## Memory and reset

- Xác định read latency, write commitment, collision behavior, reset cancellation và response validity tại từng adapter boundary.
- Reset control/validity theo yêu cầu; không được sử dụng payload không reset nếu chưa có transaction hợp lệ.
- Bảo toàn nội dung SRAM đã commit khi reset contract yêu cầu giữ dữ liệu.
- Không suy diễn rằng reset một request sẽ hủy write đã commit.
- Quartus memory primitive chỉ được nằm trong `quartus_word_ram`; các assignment về placement/routing/pin/physical thuộc backend.
- SRAM ASIC, clock-gating cell và các technology cell khác cần wrapper hoặc integration layer riêng với portable contract tường minh.

## Nên dùng / tránh dùng

| Nên dùng | Tránh dùng |
|---|---|
| Named pipeline valid and operand registers | A helper that implicitly advances transactions |
| Explicit extension before addition and a named rounding step | Unsized arithmetic with accidental truncation |
| Static lane replication with clear owners | Runtime-bounded hardware loops |
| Adapter response-valid and commit/busy signals | Assuming that request acceptance means completion |

## Tài liệu liên quan

[Current numeric contracts](full_rtl_language.md#hợp-đồng-số-học) · [Memory binding](asic_memory_binding.md) · [Verification](../verification/README.md) · [Repository working policy](../../AGENTS.md)
