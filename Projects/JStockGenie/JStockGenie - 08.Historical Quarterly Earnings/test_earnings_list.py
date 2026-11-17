import csv
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from SNP_Earnings_By_List import read_tickers, run_batch


class BatchTests(unittest.TestCase):
    def test_list_format(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "list.ini"
            path.write_text("\ufeff[Tickers]\naapl\n# comment\nMSFT ; note\nAAPL\nBRK.B\n", encoding="utf-8")
            self.assertEqual(read_tickers(path), ["AAPL", "MSFT", "BRK.B"])
            path.write_text("AAPL,MSFT", encoding="utf-8")
            with self.assertRaises(ValueError):
                read_tickers(path)

    def test_partial_failure_and_symbol_mapping(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "earnings.csv"
            with patch("SNP_Earnings_By_List.fetch_yahoo_earnings", side_effect=[
                ValueError("Unavailable"), [], [{"symbol": "BRK-B", "reported_date": "2025-01-01"}],
            ]) as fetch:
                self.assertEqual(run_batch(["BAD", "EMPTY", "BRK.B"], path, delay=0), 1)
                self.assertEqual(fetch.call_args.args[0], "BRK-B")
            with path.open(newline="") as stream:
                self.assertEqual(list(csv.DictReader(stream))[0]["symbol"], "BRK.B")
            with path.with_name("earnings_status.csv").open(newline="") as stream:
                self.assertEqual([row["status"] for row in csv.DictReader(stream)], ["error", "no_results", "ok"])
