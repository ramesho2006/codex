import unittest
from datetime import date
from unittest.mock import patch

from SNP_Earnings_By_Scrip import fetch_earnings, normalize_earnings, normalize_yahoo


class EarningsTests(unittest.TestCase):
    def test_yahoo_filters_scheduled_and_preserves_percent_units(self):
        import pandas as pd
        frame = pd.DataFrame({
            "EPS Estimate": [2.35, 2.0, float("nan")],
            "Reported EPS": [2.4, float("nan"), float("nan")],
            "Surprise(%)": [2.26, float("nan"), -3.0],
        }, index=pd.to_datetime(["2025-01-30", "2025-04-30", "2004-01-01"]).tz_localize("America/New_York"))
        rows = normalize_yahoo(frame, "AAPL", date(2025, 1, 30), date(2025, 4, 30))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["surprise_percentage"], 2.26)
        self.assertEqual(rows[0]["fiscal_period_end"], "")
        self.assertEqual(len(normalize_yahoo(frame, "AAPL")), 2)

    def test_report_dates_boundaries_sort_and_missing_values(self):
        payload = {"quarterlyEarnings": [
            {"reportedDate": "2024-02-01", "fiscalDateEnding": "2023-12-31", "surprisePercentage": "-2.5"},
            {"reportedDate": "2024-05-01", "reportedEPS": "None", "surprisePercentage": "0"},
            {"reportedDate": "2024-08-01"},
            {"reportedDate": "None"},
        ]}
        rows = normalize_earnings(payload, "aapl", date(2024, 2, 1), date(2024, 5, 1))
        self.assertEqual([row["reported_date"] for row in rows], ["2024-05-01", "2024-02-01"])
        self.assertEqual(rows[0]["reported_eps"], "")
        self.assertEqual(rows[0]["surprise_percentage"], "0")
        self.assertEqual(rows[1]["surprise_percentage"], "-2.5")
        self.assertEqual(rows[1]["symbol"], "AAPL")

    def test_provider_failures(self):
        for payload in ({}, [], {"Note": "rate limit"}, {"Information": "key"}, {"Error Message": "ticker"}):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                normalize_earnings(payload, "AAPL")

    def test_invalid_input_does_not_request(self):
        with patch("SNP_Earnings_By_Scrip.urlopen") as request:
            with self.assertRaises(ValueError):
                fetch_earnings("AAPL", "")
            with self.assertRaises(ValueError):
                fetch_earnings("AAPL", "test", date(2025, 1, 1), date(2024, 1, 1))
            request.assert_not_called()


if __name__ == "__main__":
    unittest.main()
