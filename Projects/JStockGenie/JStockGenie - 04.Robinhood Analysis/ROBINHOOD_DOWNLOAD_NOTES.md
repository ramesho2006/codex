# Robinhood Download Notes

Reviewed source: https://github.com/arungeorge101/myRobinhoodData

## What The GitHub Repo Does

- Uses a browser-copied Robinhood bearer token.
- Calls authenticated Robinhood API endpoints with `requests`.
- Uses pagination by following the `next` URL.
- Exports:
  - watchlist from `/watchlists/Default/`
  - stock/equity order history from `/orders/`
  - option order history from `/options/orders/`
- Writes JSON and XLS output with `tablib`.

## Gaps For This Project

- It exports historical orders, not current equity/ETF positions.
- It does not export current option positions.
- It writes XLS, while this project mostly uses CSV.
- It assumes one token file and does not organize dated runs.
- The summary logic groups options only by ticker, not by contract, strike, expiration, and option type.

## Local Adaptation

`download_robinhood_current.py` keeps the repo's useful pattern, but changes the output for JStockGenie:

- CSV-first output.
- Dated download folders under `downloads\YYYYMMDD_HHMMSS`.
- Current equity/ETF positions from `/positions/?nonzero=true`.
- Current option positions from `/options/positions/?nonzero=true`.
- Equity/ETF order history from `/orders/`.
- Option order history from `/options/orders/`.
- Raw JSON saved beside the CSV files for audit/debugging.

## Authentication

The script does not contain secrets. Provide a bearer token in one of these ways:

```powershell
$env:RH_BEARER_TOKEN = "your_token_here"
python .\download_robinhood_current.py
```

Or put only the token value in:

```text
D:\Codex\Projects\JStockGenie\JStockGenie - 04.Robinhood Analysis\token.txt
```

Do not commit or share `token.txt`.

## Expected CSV Outputs

- `current_equity_etf_positions.csv`
- `equity_etf_order_history.csv`
- `current_option_positions.csv`
- `option_order_history.csv`

## Notes

- ETF versus single-stock classification depends on Robinhood's `instrument_type` field. If it is not specific enough, a later enrichment step can join symbols against ETF.com, Yahoo Finance, or an internal ETF symbol list.
- Robinhood's private API can change. If an endpoint returns 401, the token has expired or lacks access. If an endpoint returns 404, the endpoint path may need to be updated.
- This script only performs GET requests; it cannot place, review, or cancel orders.

