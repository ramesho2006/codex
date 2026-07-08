# Robinhood Portfolio Snapshot - 2026-06-28

Source: Robinhood connector portfolio endpoint.

Amounts are in USD. Account numbers are masked.

| Account | Nickname | Brokerage Type | Portfolio Value | Equity Value | Options Value | Cash | Buying Power | Notes |
|---|---|---|---:|---:|---:|---:|---:|---|
| ending 0302 | My Trading | individual cash | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | Default account; no current value reported. |
| ending 0097 |  | ira_traditional margin | 33,326.86 | 35,355.24 | -3,903.00 | 1,874.62 | 1,849.41 | Contains equity and negative options exposure. |
| ending 9459 |  | ira_roth cash | 39,121.46 | 0.00 | -770.00 | 39,891.46 | 1,641.46 | Mostly cash with negative options exposure. |
| ending 1832 |  | individual managed margin | 0.11 | 0.00 | 0.00 | 0.11 | 0.11 | Managed account. |
| ending 1512 | My Investments | individual margin | 211,293.20 | 226,909.97 | -17,391.00 | 1,774.23 | 1,774.23 | Largest account; equity and negative options exposure. |
| ending 1224 | My Agentic | individual cash | 457.35 | 9.02 | 0.00 | 448.33 | 448.33 | Only account accessible for agentic trade actions. |

## Observations

- `My Investments` is the largest Robinhood portfolio by value and should be the first candidate for detailed analysis if the goal is overall exposure review.
- The IRA accounts and `My Investments` show negative options value, so options risk should be summarized separately from equity holdings.
- `My Agentic` has modest value and buying power; it remains the correct account for any future approved automation tests.
- The default `My Trading` account currently reports no portfolio value or buying power.

## Next Detailed Analysis Inputs

Choose the account to analyze first:

1. `My Investments` ending `1512` for largest portfolio exposure.
2. IRA Roth ending `9459` for cash/options review.
3. IRA Traditional ending `0097` for equity/options review.
4. `My Agentic` ending `1224` for automation-ready swing-trade review.

