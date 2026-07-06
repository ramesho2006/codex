# Weekly ETF Basket Routine

Routine name: Weekly ETF Basket Routine

Use this routine when asked to run the ETF growth/dividend basket analysis.

## Inputs

Growth ETFs:
VUG, IWF, IVW, SCHG, SPYG, VBK, IWP, IUSG, EFG, IWO

Dividend ETFs:
VIG, VYM, SCHD, DGRO, SDY, DVY, FVD, NOBL, HDV, DGRW

## Steps

1. Check `jstockdata_reco_routine_runlog` for `reco_weekly_projection_refresh`.
   - If `last_run_at` is within 1 day, do not rerun SQL routines.
   - If `last_run_at` is more than 2 days old, ask the user before running `CALL reco_weekly_projection_refresh();`.
   - If the timestamp is between 1 and 2 days old, use current tables unless the user explicitly asks for a refresh.
2. Pull the top 10 holdings for each Growth ETF and each Dividend ETF.
3. Normalize symbols, including combining GOOG and GOOGL as GOOGL/GOOG.
4. For each group, rank common holdings by unique ETF appearances, combined top-10 weight, and holding rank inside each ETF.
5. Use jstockdata_reco_weekly_target_recos as the first-pass weekly target filter:
   - reco_category = 'ETF'
   - target_band_status = 'IN_BAND' preferred
   - target_profit_pct between 1% and 3% preferred
6. Use JStockGenie signal context from reco_backtest and HA recent tables when available.
   Include projection fields from the upgraded reco model:
   - trading_horizon_days
   - trading_horizon_weeks
   - upward_projection_pct
   - upward_probability_pct
   - downward_projection_pct
   - downward_probability_pct
   - expected_return_pct
   - risk_reward_ratio
   - projection_confidence_score
7. Create exactly two final basket files:
   - Custom Growth Basket_YYYYMMDD.csv
   - Custom Dividend Basket_YYYYMMDD.csv
8. Treat intermediate holdings and candidate CSVs as analysis artifacts only, not final deliverables.

## Folder Structure

Use a stable parent folder named:

03_Reports/ETF

For each run, create a dated subfolder:

03_Reports/ETF/YYYYMMDD

## Output Columns

basket_rank, symbol, name, etf_appearances, combined_top10_weight_pct,
avg_weight_per_appearing_etf_pct, signal_note, source_etfs

When projection fields are available, add:

trading_horizon_weeks, upward_projection_pct, upward_probability_pct,
downward_projection_pct, downward_probability_pct, expected_return_pct,
risk_reward_ratio, projection_confidence_score

Also include target-band fields when available:

target_profit_pct, weeklyized_target_profit_pct, target_band_status

The 1% to 3% weekly objective is a modeled target band, not a guaranteed profit.
