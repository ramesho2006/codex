"""Fetch Yahoo quarterly earnings for a file containing one ticker per line."""

import argparse
import csv
import math
import re
import sys
import time
from datetime import date
from pathlib import Path

from SNP_Earnings_By_Scrip import FIELDS, fetch_yahoo_earnings


def read_tickers(path):
    """Read UTF-8 lists; ignore comments, blank lines, and INI section headings."""
    symbols = []
    seen = set()
    for line_number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        line = re.split(r"[;#]", line, maxsplit=1)[0].strip()
        if not line or (line.startswith("[") and line.endswith("]")):
            continue
        symbol = line.upper()
        if not re.fullmatch(r"[A-Z0-9^][A-Z0-9.^=\-]*", symbol):
            raise ValueError(f"Invalid ticker at line {line_number}: expected one ticker per line.")
        if symbol not in seen:
            symbols.append(symbol)
            seen.add(symbol)
    if not symbols:
        raise ValueError("The input file contains no tickers.")
    return symbols


def run_batch(symbols, output_path, start=None, end=None, delay=1.0):
    """Write each ticker immediately; retain successes if another ticker fails."""
    status_path = output_path.with_name(output_path.stem + "_status.csv")
    count = failures = empty = 0
    with output_path.open("w", newline="", encoding="utf-8") as output, \
            status_path.open("w", newline="", encoding="utf-8") as status_output:
        writer = csv.DictWriter(output, fieldnames=FIELDS)
        status_writer = csv.DictWriter(status_output, fieldnames=("symbol", "status", "rows", "message"))
        writer.writeheader()
        status_writer.writeheader()
        for index, symbol in enumerate(symbols, 1):
            if index > 1:
                time.sleep(delay)
            print(f"[{index}/{len(symbols)}] {symbol}", flush=True)
            try:
                # Yahoo uses BRK-B / BF-B instead of BRK.B / BF.B.
                yahoo_symbol = symbol.replace(".", "-") if symbol in ("BRK.B", "BRK.A", "BF.B", "BF.A") else symbol
                rows = fetch_yahoo_earnings(yahoo_symbol, start, end)
            except (ValueError, OSError) as exc:
                failures += 1
                status_writer.writerow(dict(symbol=symbol, status="error", rows=0, message=str(exc)))
                print(f"  Failed: {exc}", file=sys.stderr, flush=True)
            else:
                for row in rows:
                    row["symbol"] = symbol
                writer.writerows(rows)
                count += len(rows)
                empty += not rows
                status_writer.writerow(dict(symbol=symbol, status="ok" if rows else "no_results",
                                             rows=len(rows), message=""))
                print(f"  {len(rows)} rows", flush=True)
            output.flush()
            status_output.flush()
    print(f"Saved {count} rows to {output_path.resolve()}")
    print(f"Tickers: {len(symbols)}; failed: {failures}; no results: {empty}")
    print(f"Status report: {status_path.resolve()}")
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ticker_file", type=Path, help="File containing one ticker per line")
    parser.add_argument("--csv", type=Path, help="Output CSV (default: SNP_Earnings_<list-name>.csv in current directory)")
    parser.add_argument("--start", type=date.fromisoformat, help="Inclusive first report date, YYYY-MM-DD")
    parser.add_argument("--end", type=date.fromisoformat, help="Inclusive last report date, YYYY-MM-DD")
    parser.add_argument("--date", type=date.fromisoformat, help="Exact report date")
    parser.add_argument("--delay", type=float, default=1.0, help="Seconds between tickers (default: 1)")
    args = parser.parse_args()
    if args.date and (args.start or args.end):
        parser.error("--date cannot be combined with --start or --end")
    start, end = args.date or args.start, args.date or args.end
    if start and end and start > end:
        parser.error("--start must be on or before --end")
    if not math.isfinite(args.delay) or args.delay < 0:
        parser.error("--delay must be a finite nonnegative number")
    output = args.csv or Path(f"SNP_Earnings_{args.ticker_file.stem}.csv")
    status = output.with_name(output.stem + "_status.csv")
    if args.ticker_file.resolve() in (output.resolve(), status.resolve()):
        parser.error("Output paths must not overwrite the input list")
    try:
        symbols = read_tickers(args.ticker_file)
        return run_batch(symbols, output, start, end, args.delay)
    except (OSError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Interrupted. Completed ticker results remain in the CSV.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
