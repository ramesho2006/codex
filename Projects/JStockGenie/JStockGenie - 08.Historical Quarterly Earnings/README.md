# Historical quarterly earnings

Python 3.10+. Yahoo Finance is the default source and needs no API key:

```powershell
python -m pip install -r requirements.txt
python SNP_Earnings_By_Scrip.py AAPL
python SNP_Earnings_By_Scrip.py AAPL --start 2023-01-01 --end 2025-12-31 --csv AAPL_earnings.csv
python SNP_Earnings_By_Scrip.py AAPL --date 2025-01-30
```

Yahoo fetches the latest 100 calendar entries, including scheduled events before
filtering them out. This is a bounded history, not a guarantee of complete coverage;
older dates beyond those entries are unavailable. Scheduled entries without actual
EPS or surprise data are excluded. Yahoo does not supply fiscal period end in this
table, so that column is blank. Duplicate report dates from Yahoo are preserved.
Surprises are already percentage points (4.52 means 4.52%, not 452%). They may
differ from calculations using the rounded EPS values shown. Windows trusted server
certificates are included in a temporary CA bundle with TLS verification enabled.

The optional Alpha Vantage source uses only the Python standard library:

Get an [Alpha Vantage API key](https://www.alphavantage.co/support/#api-key).
Access, history coverage, and rate limits depend on the provider and your plan.
From this directory, run in PowerShell:

```powershell
$env:ALPHAVANTAGE_API_KEY = "YOUR_API_KEY"
python SNP_Earnings_By_Scrip.py AAPL --source alphavantage
```

Output includes the ticker, actual reporting date, fiscal period end, reported EPS,
estimated EPS, and the provider's earnings surprise percentage. A positive surprise
means EPS exceeded the estimate; a negative surprise means it missed. This is not
the stock price change or quarterly earnings growth. The percentage is preserved
as reported by the provider rather than recalculated; unavailable values display
as N/A and export as blank fields.

Date filters are inclusive and use the **report date**, not the fiscal period end.
Results are sorted newest first. Alpha Vantage includes all returned quarterly records;
Yahoo is limited to the latest 100 calendar entries. Records with no reporting date are excluded. CSV output replaces
the specified file. The API key is read only from the environment.

API reference: [Alpha Vantage EARNINGS](https://www.alphavantage.co/documentation/#earnings).

Run offline checks with `python -m unittest -v`.

## Batch ticker list

Keep `SNP_Earnings_By_List.py` beside `SNP_Earnings_By_Scrip.py`. Run:

```powershell
python SNP_Earnings_By_List.py "D:\DB011-JWORK\JStockTrend\list\JStockSNP500List.ini"
python SNP_Earnings_By_List.py "D:\DB011-JWORK\JStockTrend\list\JStockSNP500List.ini" --start 2023-01-01 --end 2025-12-31
```

The default output is `SNP_Earnings_JStockSNP500List.csv` in the current directory.
Use `--csv "D:\output\my_earnings.csv"` to choose a different path (parent must exist).
Each row includes the input ticker. Results are grouped in list order, newest report
first within each ticker. The companion `SNP_Earnings_JStockSNP500List_status.csv`
records success, no matching results, or an error for every processed ticker.
Files are replaced on each run. Successful results are flushed after each ticker;
individual fetch failures do not stop the remaining list. Exit code 1 indicates
one or more failures; 0 indicates completion without failures.

Input is UTF-8, one ticker per line (as in your existing INI list). Blank lines,
`#`/`;` comments, INI section headers, and duplicate tickers are ignored. Key-value
INI entries are not supported. BRK.A/BRK.B and BF.A/BF.B are translated to Yahoo's
hyphenated symbols for requests; the CSV retains the original input symbols.
Requests are sequential with a one-second pause; adjust with `--delay 2` if needed.
Yahoo's 100-calendar-entry history limit applies separately to each ticker.
