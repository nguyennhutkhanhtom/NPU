# Model tương thích với llm_soc

> **Category: GUIDE.**

[Tài liệu](../README.md) → [Demo](README.md) → **Tương thích model**

## Model đang được exporter hỗ trợ

Exporter hiện pin **NanoFable-1M-ternary seed1** bằng SHA-256, với bốn layer,
128 channel, bốn head, FFN 384 channel và vocabulary 4.096. Kiến trúc dùng affine
RMSNorm, RoPE, causal attention, SwiGLU và tied embedding/head. Context RTL tối đa
128 vị trí; tổng prompt token và số token mới yêu cầu phải nằm trong giới hạn này.

| Dữ liệu | Cách export |
|---|---|
| Embedding và tied head | S8 codes, scale riêng từng hàng U24/F24 |
| Bảy ternary matrix mỗi layer | Giữ ba mức -1/0/+1; mã 2 bit và scale đã train |
| RMSNorm gain | S16/F12 |
| Activations và KV | S24/F16 theo reference số nguyên |
| Tokenizer | tokenizer.json đã pin, token ID 12 bit |

Bộ nhớ full graph là parameter 768 KiB, KV 384 KiB và vector workspace 9 KiB.
[Cấu hình và format](../design/full_rtl_language.md) mô tả hợp đồng chi tiết.

## Thay checkpoint cần những gì?

CLI hiện tại thay được prompt, số token, temperature, seed và minimum token.
Nó chưa có tham số chọn một checkpoint bất kỳ: exporter kiểm tra SHA của file
model và yêu cầu geometry/operators đã hỗ trợ.

Để thêm checkpoint khác, cần đối chiếu tensor names, shape, ternary encoding,
normalization, positional encoding, tokenizer và layout bộ nhớ; sau đó cập nhật
exporter/reference và kiểm chứng số học. Nếu đổi geometry hoặc operator trên
RTL, cần evidence unit/graph và timing mới trước application.

Checkpoint seed0 cùng kiến trúc là một training replica khác. Việc có file
seed0 trong upstream metadata chưa chứng minh nó đã export hoặc chạy trên RTL.
Numeric matching của một checkpoint cũng chưa chứng minh khả năng hội thoại
hay chất lượng trên dataset.

## Tài liệu khảo sát cũ

[Khảo sát model cho core 32 PE](legacy/model_candidates.md) giữ các tính toán
MNIST/MLGRU/Char32 và dung lượng 32+8 KiB của kiến trúc matmulfree. Dùng tài liệu
đó trong phạm vi legacy; chọn NanoFable hiện tại theo hướng dẫn ở trên.
