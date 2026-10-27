# Hệ thống tests

> **Category: GUIDE.** Điểm vào ngắn. Chi tiết từng block và reference của regression legacy:
> [Hệ thống tests và regression legacy](../docs/verification/legacy_regression.md).

| Thiết kế | Entry point | Hướng dẫn |
|---|---|---|
| llm_soc synthetic units/graph | `tests/full_rtl/run_units.ps1` | [Verification guide](../docs/verification/README.md) · [full_rtl](full_rtl/README.md) |
| llm_soc model thật | `tests/full_rtl/run_application.ps1` | [NanoFable từng bước](../docs/demos/language.md) |
| matmulfree legacy | `tests/run.ps1` | [Regression legacy](../docs/verification/legacy_regression.md#regression-legacy) |

Regression legacy, chạy từ thư mục gốc (cần Python 3.10+ và ModelSim):

```powershell
./tests/run.ps1 -Block All
python tests/reference.py --check
```

Assets checkpoint: [language_demo](language_demo/README.md). Bằng chứng MNIST cũ: [model_demo](model_demo/README.md).
