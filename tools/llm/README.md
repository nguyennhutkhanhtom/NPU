# LUT generation

> **Category: GUIDE.**

Lookup tables store precomputed fixed-point function samples so hardware does not
evaluate expensive transcendental functions at runtime. See [fixed-point
fundamentals](../../docs/00-start-here/fundamentals.md#bits-signed-values-and-fixed-point-numbers)
before changing formats or rounding.

[Documentation hub](../../docs/README.md) · [Numeric tables](../../docs/design/full_rtl_language.md)

`generate_tables.py` regenerates the explicit exp/Gumbel combinational tables.
Math tests independently check their numeric entries; changing generated RTL
requires fresh unit and hardware gates before pretrained application execution.

Full-graph tests and applications use [the Questa runners](../../tests/full_rtl/README.md).
The former native simulator and evidence merger have no callers in those runners
and are preserved byte-exact in [cleanup history](../../docs/history/helper_cleanup1/manifest.json).
Historical tags keep their original helper hashes and results.
