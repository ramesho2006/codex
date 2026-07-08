# Weekly Options Recos Routine

Routine name: Weekly Options Recos

Use this routine when asked to generate weekly options recommendations for non-Agentic/manual accounts.

## Purpose

Generate manual-only options candidates using the JStockGenie target-band, projection, and momentum tables. No options orders are automated.

## Data Sources

- `jstockdata_reco_weekly_target_recos`
- `jstockdata_reco_options`
- `jstockdata_reco_momentum_signal`
- `jstockdata_reco_projection`
- live option chain review by the user before any order

## SQL Freshness

Before generating options recos, check:

```sql
SELECT routine_name, last_run_at, last_status, last_message
FROM jstockdata_reco_routine_runlog
WHERE routine_name IN (
  'reco_weekly_master_refresh',
  'reco_options',
  'reco_projection_enrich_outputs',
  'reco_momentum_refresh',
  'reco_weekly_target_refresh'
)
ORDER BY routine_name;
```

- Within 1 day: use current tables.
- More than 2 days old: ask before running `CALL reco_weekly_master_refresh();`.
- Between 1 and 2 days: use current tables unless the user explicitly asks for refresh.

## Candidate Rules

Use only rows where:

- `reco_category = 'OPTIONS'`
- `account_scope = 'Non-Agentic Manual Only'`
- `target_band_status = 'IN_BAND'` preferred
- `weeklyized_target_profit_pct` is between 1% and 3%

Momentum alignment:

- Bullish momentum can support cash-secured put candidates.
- Bearish or weakening momentum can support covered-call review only when shares are already held.
- Reversal-risk momentum should normally be avoided for new premium-selling exposure.

## Required Manual Review

Before the user places any option order manually, verify:

- bid/ask spread
- volume and open interest
- DTE and expiration date
- strike distance from current price
- estimated premium income
- estimated cash-secured put collateral or covered-share requirement
- assignment risk
- account options approval level

## Output Location

For each run, create:

`03_Reports/Options/YYYYMMDD`

Suggested file:

- `Weekly_Options_Manual_Recos_YYYYMMDD.csv`
- `Weekly_Options_Summary_YYYYMMDD.md`

## Guardrails

- Never automate options orders.
- Never treat modeled 1% to 3% weeklyized premium as guaranteed.
- Always label output as manual-only.
