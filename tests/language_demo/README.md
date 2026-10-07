# Assets NanoFable đã pin

> **Category: GUIDE.**

[Tài liệu](../../docs/README.md) → [Demo NanoFable](../../docs/demos/language.md) → **Assets**

Thư mục này cung cấp checkpoint/tokenizer và dependencies cho application
llm_soc. Model revision, source revision, file sizes và SHA-256 nằm trong
[upstream_manifest.json](upstream_manifest.json).

## Tải hoặc kiểm tra

Chạy từ repository root với Python 3.11/3.12:

```powershell
$pythonExe = 'C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& tests/language_demo/setup.ps1 -Python $pythonExe
```

Setup cài NumPy 2.3.5, safetensors 0.6.2 và tokenizers 0.22.1 vào packages/,
rồi tải/kiểm tra 12 assets trong upstream/. Checkpoint và packages nằm local,
được Git ignore. Bước setup chưa chạy model inference.

Nếu file đã có, kiểm tra mà không tải lại:

```powershell
& $pythonExe tests/language_demo/fetch_assets.py --check
```

Để chạy model, mở [hướng dẫn NanoFable](../../docs/demos/language.md). Export và
CPU reference của application chỉ chạy khi đúng source/config đã qua cả bảy
nhóm units/graph và full-top all-corner timing gate.

## Bằng chứng hybrid trước đây

[results.json](results.json) và [báo cáo hybrid](../../docs/demos/legacy/nanofable_hybrid.md)
giữ kết quả CPU generation cùng linear-only RTL của flow cũ. Runner hybrid đã
được loại bỏ; đây là bằng chứng lịch sử, không phải application toàn graph.
