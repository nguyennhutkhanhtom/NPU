"""Verify report totals against actual archived Quartus reports."""
from pathlib import Path
import unittest
from record import stage_counts

ROOT = Path(__file__).resolve().parents[2]


class ReportTotals(unittest.TestCase):
    def test_actual_singular_warning(self):
        text = (ROOT / 'docs/verification/timing/fullrtl100_fanout1/llm_soc.sta.rpt').read_text(encoding='utf-8', errors='replace')
        counts = stage_counts(text)
        self.assertEqual((counts['errors'], counts['warnings']), (0, 1))
        self.assertIn(332148, [d['id'] for d in counts['reported_diagnostics']])

    def test_actual_plural_warnings(self):
        tag = ROOT / 'docs/verification/timing/fullrtl100_fanout1'
        for stage, warnings in [('map', 12), ('fit', 4)]:
            with self.subTest(stage=stage):
                counts = stage_counts((tag / f'llm_soc.{stage}.rpt').read_text(encoding='utf-8', errors='replace'))
                self.assertEqual((counts['errors'], counts['warnings']), (0, warnings))

    def test_incomplete_report_is_unknown(self):
        counts = stage_counts('Info: Quartus Prime Timing Analyzer started\n')
        self.assertIsNone(counts['errors'])
        self.assertIsNone(counts['warnings'])


if __name__ == '__main__':
    unittest.main()
