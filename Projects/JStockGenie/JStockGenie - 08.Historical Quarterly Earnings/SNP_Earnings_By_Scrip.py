"""Fetch quarterly EPS and earnings surprises from Yahoo Finance or Alpha Vantage."""

import argparse
import csv
import json
import os
import sys
import ssl
import tempfile
from datetime import date
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import urlopen


FIELDS = ("symbol", "reported_date", "fiscal_period_end", "reported_eps",
          "estimated_eps", "surprise_percentage")


def normalize_yahoo(frame, symbol, start=None, end=None):
    import pandas as pd
    if frame is None:
        raise ValueError("Yahoo returned no earnings table. Check the ticker or retry later.")
    required = {"EPS Estimate", "Reported EPS", "Surprise(%)"}
    if not required.issubset(frame.columns):
        raise ValueError("Yahoo earnings columns changed; update yfinance.")
    rows = []
    for timestamp, record in frame.iterrows():
        if pd.isna(timestamp):
            continue
        reported = timestamp.date()
        # Exclude scheduled events without results; preserve older surprise-only rows.
        if pd.isna(record["Reported EPS"]) and pd.isna(record["Surprise(%)"]):
            continue
        if (start and reported < start) or (end and reported > end):
            continue
        def value(key):
            return "" if pd.isna(record[key]) else record[key]
        rows.append(dict(zip(FIELDS, (symbol.upper(), reported.isoformat(), "",
                                     value("Reported EPS"), value("EPS Estimate"), value("Surprise(%)")))))
    return sorted(rows, key=lambda row: row["reported_date"], reverse=True)


def fetch_yahoo_earnings(symbol, start=None, end=None):
    symbol = symbol.strip().upper()
    if not symbol:
        raise ValueError("A ticker symbol is required.")
    if start and end and start > end:
        raise ValueError("Start date must be on or before end date.")
    try:
        import certifi
        import yfinance as yf
        from curl_cffi import requests
    except ImportError:
        raise ValueError("Install Yahoo dependencies: python -m pip install -r requirements.txt") from None
    # Include Windows enterprise roots, without disabling certificate verification.
    with tempfile.TemporaryDirectory(prefix="jstockgenie-") as directory:
        bundle = Path(directory) / "ca.pem"
        certificates = Path(certifi.where()).read_text(encoding="ascii")
        if sys.platform == "win32":
            for store in ("ROOT", "CA"):
                for certificate, encoding, trust in ssl.enum_certificates(store):
                    if encoding == "x509_asn" and (trust is True or "1.3.6.1.5.5.7.3.1" in trust):
                        certificates += "\n" + ssl.DER_cert_to_PEM_cert(certificate)
        bundle.write_text(certificates, encoding="ascii")
        try:
            with requests.Session(impersonate="chrome", verify=str(bundle)) as session:
                frame = yf.Ticker(symbol, session=session).get_earnings_dates(limit=100)
        except Exception as exc:
            raise ValueError(f"Yahoo earnings request failed ({type(exc).__name__}). Check connectivity or retry later.") from None
    return normalize_yahoo(frame, symbol, start, end)


def normalize_earnings(payload, symbol, start=None, end=None):
    """Return newest-first rows, filtered inclusively by actual report date."""
    if start and end and start > end:
        raise ValueError("Start date must be on or before end date.")
    if not isinstance(payload, dict):
        raise ValueError("Unexpected earnings API response.")
    for key in ("Error Message", "Note", "Information"):
        if payload.get(key):
            # Do not echo provider messages that could contain credentials.
            raise ValueError("API rejected the request. Check the ticker, API key, plan access, and rate limit.")
    quarters = payload.get("quarterlyEarnings")
    if not isinstance(quarters, list):
        raise ValueError("No quarterly earnings returned. Check the ticker and provider coverage.")
    rows = []
    for quarter in quarters:
        if not isinstance(quarter, dict):
            raise ValueError("Unexpected quarterly earnings record.")
        reported = quarter.get("reportedDate")
        if reported in (None, "", "None", "null", "N/A"):
            continue  # Undated records cannot be included in report-date history.
        reported_date = date.fromisoformat(reported)
        if (start and reported_date < start) or (end and reported_date > end):
            continue

        def value(key):
            item = quarter.get(key)
            return "" if item in (None, "", "None", "null", "N/A") else item

        rows.append(dict(zip(FIELDS, (
            symbol.upper(), reported_date.isoformat(), value("fiscalDateEnding"),
            value("reportedEPS"), value("estimatedEPS"), value("surprisePercentage"),
        ))))
    return sorted(rows, key=lambda row: row["reported_date"], reverse=True)


def fetch_earnings(symbol, api_key, start=None, end=None):
    """Fetch all available quarterly history; apply local report-date filters."""
    symbol = symbol.strip().upper()
    if not symbol or not api_key.strip():
        raise ValueError("A ticker symbol and ALPHAVANTAGE_API_KEY are required.")
    if start and end and start > end:
        raise ValueError("Start date must be on or before end date.")
    query = urlencode({"function": "EARNINGS", "symbol": symbol, "apikey": api_key.strip()})
    try:
        with urlopen("https://www.alphavantage.co/query?" + query, timeout=30) as response:
            payload = json.load(response)
    except HTTPError as exc:
        raise ValueError(f"Earnings service returned HTTP {exc.code}.") from None
    except (URLError, TimeoutError, OSError):
        raise ValueError("Could not reach the earnings service. Check your connection and retry.") from None
    except (ValueError, UnicodeError):
        raise ValueError("Earnings service returned invalid JSON.") from None
    return normalize_earnings(payload, symbol, start, end)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ticker", help="Ticker symbol, e.g. AAPL")
    parser.add_argument("--source", choices=("yahoo", "alphavantage"), default="yahoo")
    parser.add_argument("--start", type=date.fromisoformat, help="First report date (YYYY-MM-DD), inclusive")
    parser.add_argument("--end", type=date.fromisoformat, help="Last report date (YYYY-MM-DD), inclusive")
    parser.add_argument("--date", type=date.fromisoformat, help="An exact report date; cannot combine with start/end")
    parser.add_argument("--csv", type=Path, help="Also save the results to this CSV path")
    args = parser.parse_args()
    if args.date and (args.start or args.end):
        parser.error("--date cannot be combined with --start or --end")
    try:
        if args.source == "yahoo":
            rows = fetch_yahoo_earnings(args.ticker, args.date or args.start, args.date or args.end)
        else:
            rows = fetch_earnings(args.ticker, os.getenv("ALPHAVANTAGE_API_KEY", ""),
                                  args.date or args.start, args.date or args.end)
        if args.csv:
            with args.csv.open("w", newline="", encoding="utf-8") as output:
                writer = csv.DictWriter(output, fieldnames=FIELDS)
                writer.writeheader()
                writer.writerows(rows)
        if not rows:
            print("No dated quarterly earnings matched the requested dates.")
            return 0
        headers = ("Ticker", "Reported date", "Fiscal end", "Actual EPS", "Estimate EPS", "Surprise %")
        display = [[str(row[field]) or "N/A" for field in FIELDS] for row in rows]
        widths = [max(len(headers[i]), *(len(row[i]) for row in display)) for i in range(len(FIELDS))]
        for row in [headers, *display]:
            print("  ".join(value.ljust(width) for value, width in zip(row, widths)))
        return 0
    except (ValueError, OSError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
