# Gap Trade Strategy — Daily OHLC Proxy Backtest

**Run date:** 20261003  
**Market data through:** 20261002  
**Gap entries simulated:** 11,398  
**Entry dates:** 20240103–20260921  
**Database:** MySQL 8; `jstocksnp.jstockdata_gap_trades` joined to `jstockdata_hist`

## Headline result

- Wins: **2,547/11,398 (22.35%)**; losses: **8,851**.
- Mean outcome: **-0.059 R/trade**; median: **-1.00 R**.
- Sum of independent trade outcomes: **-668.95 R**, or **$-66,894.52** if every trade independently risked $100.
- Exit reasons: stop 6,703, stop_same_bar_conservative 2,184, gap_fill 1,583, tp2 645, stop_gap_open 230, session10_close 53.
- Sides: 5,458 long and 5,940 short.

The normalized dollars are a per-trade comparison unit, **not an account-equity curve or a realized portfolio P&L**. The sum assumes a fresh $100 risk budget for every signal, ignores concurrent-position limits, overlap, compounding, and capital constraints.

## Method used

- Qualified `ABS(gap_pct)` from 3% through 19%, inclusive. This filter selected 11,473 records in the table; 75 recent records were omitted because ten full daily sessions of subsequent data were unavailable.
- User direction: gap up → short; gap down → long.
- **Entry proxy:** the gap-day daily open. The intended 9:45 a.m. ET price is not stored in the database, so the requested entry time cannot be reconstructed exactly.
- 1% adverse stop; TP#1 at 3% closes half; TP#2 at 5% closes the rest. The prior close is also treated as a take-profit, closing the remaining quantity if reached before the applicable percentage target.
- Entry session counts as session 1; any remaining shares exit at that session's close if session 10 is reached.
- Uses daily OHLC bars. If a bar touches both stop and a favorable target, assumes the stop happens first. If the market opens through the stop, uses the open as the exit price.
- Assumes fractional half-position accounting for the 50% scale-out. Results are gross of commissions, slippage, borrow costs, and taxes.

## Important limits

This is an **indicative daily-bar proxy**, not a faithful 9:45 intraday backtest. Daily bars include price movement before 9:45 on the entry day, and do not show the order of high/low events. They therefore cannot determine whether an intraday stop or target happened after entry, nor resolve same-bar event sequence. The proxy may misstate outcomes materially.

The data also does not provide historical short availability, the unresolved trailing-stop alternative was not modeled, no separate cumulative daily loss cap was applied, and no historical ranking rule was available to select at most 10 simultaneous positions. Each signal was evaluated independently. Do not treat the results as validated strategy performance or use them as a live-trading forecast.

## Best 10 scrips by normalized P&L*

| Scrip | Trades | Win rate | Avg R | Total R | Normalized P&L* |
|---|---:|---:|---:|---:|---:|
| HUM | 31 | 51.6% | 1.135 | 35.19 | $3,518.51 |
| WDAY | 47 | 34.0% | 0.554 | 26.05 | $2,604.57 |
| GOOGL | 25 | 40.0% | 1.019 | 25.47 | $2,547.21 |
| P | 68 | 30.9% | 0.343 | 23.36 | $2,335.55 |
| GOOG | 24 | 37.5% | 0.931 | 22.34 | $2,233.96 |
| SW | 53 | 39.6% | 0.406 | 21.52 | $2,152.46 |
| VRT | 120 | 26.7% | 0.167 | 20.04 | $2,004.07 |
| COO | 15 | 53.3% | 1.311 | 19.67 | $1,966.77 |
| META | 29 | 37.9% | 0.677 | 19.62 | $1,962.44 |
| DHI | 26 | 38.5% | 0.729 | 18.95 | $1,895.16 |

## Worst 10 scrips by normalized P&L*

| Scrip | Trades | Win rate | Avg R | Total R | Normalized P&L* |
|---|---:|---:|---:|---:|---:|
| LITE | 154 | 12.3% | -0.463 | -71.23 | $-7,123.21 |
| SMCI | 156 | 12.8% | -0.421 | -65.60 | $-6,560.44 |
| BE | 169 | 15.4% | -0.305 | -51.56 | $-5,156.10 |
| ALB | 89 | 13.5% | -0.524 | -46.66 | $-4,665.59 |
| COHR | 138 | 15.2% | -0.325 | -44.92 | $-4,491.85 |
| CIEN | 94 | 12.8% | -0.413 | -38.83 | $-3,883.27 |
| ON | 83 | 14.5% | -0.418 | -34.73 | $-3,473.23 |
| INTC | 97 | 15.5% | -0.335 | -32.50 | $-3,250.36 |
| COIN | 144 | 18.1% | -0.222 | -31.97 | $-3,197.45 |
| MU | 139 | 18.0% | -0.225 | -31.31 | $-3,131.23 |

* Normalized P&L assumes $100 risk per individual trade. Full 600-scrip results are in `Gap_Trade_Backtest_By_Scrip_20261003.csv`; trade-level calculations are in `Gap_Trade_Backtest_Trades_20261003.csv`.
