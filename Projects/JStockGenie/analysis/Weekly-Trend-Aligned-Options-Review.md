# Weekly Trend-Aligned Options Review

Reusable JStockGenie + OptionStrat analysis, established October 31, 2026.

Run it by asking: **“Run the Weekly Trend-Aligned Options Review for this week.”**

Explicit skill invocation: `$weekly-trend-options-review`.

The reusable instructions are saved in [SKILL.md](D:/Codex/Sessions/skills/weekly-trend-options-review/SKILL.md).

Default scope: read-only MySQL HA/SMA trend screening; weekly confirmation; OptionStrat optimizer and per-leg verification; cash-secured puts, bull put credit spreads and bear call credit spreads; 30–40 calendar DTE; absolute sell delta 0.40–0.50 and buy delta 0.20–0.30. Compare modeled PoP, approximate loss probability, maximum profit/loss, capital, ROI, liquidity and event risk. Show midpoint and bid/ask scenarios separately. Refresh all dates and quotes each run.

The complete initial analysis is preserved in [October 31 recommendations](optionstrat-20261031/recommendations.md), with the [full UP/DOWN list](optionstrat-20261031/trend_screen.md) and [structured trend data](optionstrat-20261031/trend_screen.json).

Future reports go in `analysis/weekly-trend-options-review/YYYY-MM-DD/`, retaining previous results and comparing meaningful week-over-week changes. This is a reusable, on-demand workflow; no scheduled automation has been created.

## Saved review approach

1. **Establish the as-of date.** Use America/Chicago, the latest completed market session and the intended entry date. Calculate eligible expirations afresh; never reuse last week's DTE or quotes.
2. **Verify the database read-only.** Confirm MySQL version/database and schemas for `jstockdata_hatrend`, `jstockdata_hatrend_extend`, `jstockdata_harecent` and `jstockdata_harecent_extend`. Join by symbol, date and normalized frequency; remove trailing carriage returns where present. Check freshness, missing joins and agreement between recent and historical records.
3. **Build the trend universe.** UP requires GREEN corrected HA candles and UP SMA trend; DOWN requires RED candles and DOWN SMA trend. Prefer matching weekly direction. Preserve conflicting/stale exclusions and full candidate lists. Treat HA RSI, Aroon and combined signals as supporting context. Do not interpret database `Opti_ChancePct` as options probability of profit.
4. **Select and disclose screening coverage.** Prioritize trend consistency, liquidity, event risk and capital requirements. Record which symbols were actually evaluated in OptionStrat; a focused shortlist is not exhaustive optimization.
5. **Use OptionStrat optimizer and builder.** Verify exact ticker, direction, eligible expiry and target-price assumptions. Compare return/probability weighting. Adjust the optimizer's suggestions as needed and verify each leg's absolute delta, strike, bid/ask, volume and open interest. Reject or flag noncompliant and illiquid contracts.
6. **Check events and suitability.** Verify earnings dates from primary sources, consider dividends/assignment where relevant, and flag extended trends and correlated exposure. Separate preferred, conditional and rejected candidates. Report no suitable trade when evidence warrants it.
7. **Calculate comparable returns.** Use one standard 100-share contract per leg unless otherwise specified. CSP maximum profit is premium × 100, collateral is strike × 100, maximum loss is collateral minus premium, and ROI is profit/full collateral. Spread maximum profit is net credit × 100, maximum loss is width × 100 minus credit, and ROI is profit/maximum loss. Verify contract multipliers. Show breakeven and fees/slippage assumptions.
8. **Separate pricing scenarios and probabilities.** Show midpoint results and conservative short-bid/long-ask results separately. Use OptionStrat's modeled PoP, not delta as PoP. Approximate probability of any loss is 100% minus rounded PoP; it is not probability of maximum loss. Do not reuse midpoint PoP for a different credit without recalculation. Distinguish maximum return from expected return.
9. **Rank trade-offs and archive.** Explain the probability, dollar-profit, ROI and liquidity trade-offs within each strategy. Save a dated recommendations report, full trend data, observed quotes, verified strategy links and useful screenshots. Compare meaningful changes with the previous week without treating different contracts as identical.

## MySQL weekly history

Weekly recommendation archiving is authorized in `jstocksnp.jstockdata_reco_weekly_optionstrat`. The initial six recommendations are stored with reviewed date October 31, 2026. Future reviews append dated snapshots without overwriting history. See the [database guide](weekly-trend-options-review/database-guide.md) for schema, import procedure, queries and performance-analysis limitations.

Include `collateral` in each weekly review. The weekly importer calculates and validates full strike cash for CSPs and strike-width collateral for spreads using quantity and the multiplier in `legs_json`. It is a stored numeric column in the concise 26-column schema. `roi_pct`, `pop_pct` and `breakeven` retain midpoint estimates. Amounts are USD before subtracting premium; richer risk/pricing details remain in the local report.

## Prompt provenance and logging

The [October 31 prompt log](optionstrat-20261031/prompt-log.md) preserves the user requests, implementation interpretations and a reusable weekly invocation prompt. For future reviews, save the triggering prompts and any parameter changes in that run's `prompt-log.md`; omit automatic UI metadata and never include credentials. Record dates and only record exact times if available.
