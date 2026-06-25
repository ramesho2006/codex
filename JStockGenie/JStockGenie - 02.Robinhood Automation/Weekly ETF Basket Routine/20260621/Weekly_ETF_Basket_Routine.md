# Weekly ETF Basket Routine

Routine name: Weekly ETF Basket Routine

Use this routine when asked to run the ETF growth/dividend basket analysis.

## Inputs

Growth ETFs:
VUG, IWF, IVW, SCHG, SPYG, VBK, IWP, IUSG, EFG, IWO

Dividend ETFs:
VIG, VYM, SCHD, DGRO, SDY, DVY, FVD, NOBL, HDV, DGRW

## Steps

1. Pull the top 10 holdings for each Growth ETF and each Dividend ETF.
2. Normalize symbols, including combining GOOG and GOOGL as GOOGL/GOOG.
3. For each group, rank common holdings by unique ETF appearances, combined top-10 weight, and holding rank inside each ETF.
4. Use JStockGenie signal context from reco_backtest and HA recent tables when available.
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
5. Create exactly two final basket files:
   - Custom Growth Basket_YYYYMMDD.csv
   - Custom Dividend Basket_YYYYMMDD.csv
6. Treat intermediate holdings and candidate CSVs as analysis artifacts only, not final deliverables.

## Folder Structure

Use a stable parent folder named:

Weekly ETF Basket Routine

For each run, create a dated subfolder:

Weekly ETF Basket Routine/YYYYMMDD

## Output Columns

basket_rank, symbol, name, etf_appearances, combined_top10_weight_pct,
avg_weight_per_appearing_etf_pct, signal_note, source_etfs

When projection fields are available, add:

trading_horizon_weeks, upward_projection_pct, upward_probability_pct,
downward_projection_pct, downward_probability_pct, expected_return_pct,
risk_reward_ratio, projection_confidence_score
