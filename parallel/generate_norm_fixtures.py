"""Reuse the existing NORM oracle in an isolated regression directory."""
import importlib.util
import sys
from pathlib import Path

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("norm_fixtures", root / "norm/generate_tests.py")
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)
fixtures.OUT = root / "parallel/sim/norm"
fixtures.OUT.mkdir(parents=True, exist_ok=True)
fixtures.main()
