"""Compatibility entry point for the current functional verification report."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).resolve().parents[2]/"functional/tools/report.py"),run_name="__main__")
