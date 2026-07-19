# JStockGenie - Robinhood Automation

This folder is organized around the weekly JStockGenie Robinhood workflow.

## Start Here

- `00_Runbooks/Weekly_Trading_Operations_Runbook.md` - primary weekly operating runbook.
- `00_Runbooks/Reco_SQL_Refresh_Runbook.md` - SQL freshness, refresh sequence, and validation queries.
- `01_Routines/` - routine-specific instructions for EQT, ETF, and options recommendation runs.

## Standing Instructions

- Before running weekly ETF, EQT, options, or SQL refresh routines, review this README and the current runbooks under `00_Runbooks/`.
- Log every user prompt for this chat to `D:\Codex\Prompts\JStockGenie - 02.Robinhood Automation v2.txt` using `YYYYMMDD HH:MM` followed by a divider line.
- Keep README and runbooks current whenever the weekly routine, SQL sequence, universe filter, news overlay, or recommendation logic changes.

## Folder Map

- `00_Runbooks/` - current operating runbooks and model design notes.
- `01_Routines/` - stable routine definitions used when the user asks to run weekly routines.
- `02_SQL/` - SQL migrations and reusable review queries.
- `03_Reports/` - dated weekly outputs and dry-run reports.
- `04_Journal/` - Agentic trading journal workbook and previews.
- `05_Tools/` - local helper/build scripts.
- `99_Archive/` - old duplicate folders, scratch extracts, and historical artifacts kept for reference.

## Weekly Output Locations

- EQT Agentic reports: `03_Reports/EQT/YYYYMMDD`
- ETF basket reports: `03_Reports/ETF/YYYYMMDD`
- Dry runs: `03_Reports/DryRuns/YYYYMMDD`
- Agentic journal: `04_Journal/Agentic Trading Journal/Robinhood_MyAgentic_Trading_Journal.xlsx`

## Weekly Routine Summary

1. Upload EOD data.
2. Run Java Trend model.
3. Run the single master SQL refresh routine:

   ```sql
   CALL reco_weekly_master_refresh();
   ```

   The master refresh routine runs these child routines in order:

   1. `reco_universe_status_refresh(1000)`
   2. `reco_news_signal_refresh(7)`
   3. `reco_backtest`
   4. `reco_trade`
   5. `reco_invest`
   6. `reco_options`
   7. `reco_projection_refresh`
   8. `reco_projection_enrich_outputs`
   9. `reco_momentum_refresh`
   10. `reco_predictive_direction_refresh`
   11. `reco_basket_refresh`
   12. `reco_weekly_target_refresh`

   Do not create or run a second weekly wrapper. `reco_weekly_master_refresh()` is the canonical master routine.

4. Use `jstockdata_scrips.RecoUniverseStatus = 'KEEP'` and `RecoUniverseRank <= 1000` as the active EQ/ETF universe gate for trading analysis and recommendation refreshes.
5. Fetch recent news with `05_Tools/reco_news_fetcher.py` when an API key is configured; otherwise the news overlay remains neutral.
6. Validate projections, momentum, predictive direction, news overlay, baskets, and target-band tables.
7. Generate ETF, EQT, and manual options recommendations.
8. For Agentic account, prepare orders as review-only and place only after explicit confirmation.
9. For non-Agentic accounts, user manually reviews and places ETF/options trades.
10. Update the trading journal after fills, funds, or position changes.

## Momentum Phase Guide

Use `jstockdata_reco_momentum_signal.momentum_phase` beside `momentum_direction`, `momentum_score`, and `Combined_Signal`.

| momentum_phase | Meaning | Weekly use |
|---|---|---|
| `EARLY` | Bullish momentum has recently started and acceleration is positive. | Best zone for new BUY candidates. |
| `BULLISH_ACCELERATING` | Bullish momentum is aligned across `Combined_Signal` and `LODeltaSignal`, not overextended, and acceleration is positive or neutral. | Good for bullish BUY candidates and SELL PUT review. |
| `BEARISH_ACCELERATING` | Bearish momentum is aligned across `Combined_Signal` and `LODeltaSignal`, not deeply oversold, and acceleration is negative or neutral. | Avoid new long entries; review covered-call or trim risk. |
| `MATURE` | Bullish momentum exists, but the move may be extended. | Hold or size smaller; watch profit-lock levels. |
| `WEAKENING` | Still bullish overall, but acceleration has turned negative. | Avoid aggressive new buys; consider trim/watch. |
| `NEUTRAL` | Momentum score is mixed or below threshold. | Wait for clearer confirmation. |
| `REVERSAL_RISK` | Momentum and supporting signals conflict or no longer fit a clean trend. | Avoid new buys unless there is a specific override reason. |

For weekly EQT/ETF picks, prefer `momentum_direction = 'BULLISH'` with `momentum_phase IN ('EARLY', 'BULLISH_ACCELERATING')`.

## Predictive Direction

`reco_predictive_direction_refresh()` maintains:

- `jstockdata_reco_major_pivots` - historical major local peaks/troughs using daily close, a 10-bar pivot window, and a 7% major-move filter.
- `jstockdata_reco_predictive_direction` - one latest row per scrip with daily/weekly Combined Signal, daily/weekly momentum, probability, confidence, and `weekly_verdict`.

Use `jstockdata_reco_predictive_direction` as the fast screener layer, then drill into `jstockdata_reco_major_pivots` for historical reaction context.
