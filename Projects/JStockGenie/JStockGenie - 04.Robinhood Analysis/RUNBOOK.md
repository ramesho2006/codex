# Robinhood Analysis Runbook

Updated: 2026-06-28

## Purpose

Use this workflow to analyze Robinhood accounts against JStockGenie recommendations without placing trades.

## Weekly Sequence

1. Refresh JStockGenie trend and recommendation outputs.
2. Capture Robinhood account-level portfolio snapshots.
3. Select the Robinhood account for position-level analysis.
4. Pull current equity positions for the selected account.
5. Compare positions against JStockGenie trade, investment, ETF, weekly target, and current-position outputs.
6. Produce an analysis summary with hold, trim, add, avoid, and manual-review buckets.
7. If the selected account is `My Agentic`, optionally hand approved ideas to the Robinhood automation workflow.

## JStockGenie Inputs

Primary database tables:

- `jstockdata_reco_trade`
- `jstockdata_reco_invest`
- `jstockdata_reco_options`
- `jstockdata_reco_projection`
- `jstockdata_reco_weekly_target_recos`
- `jstockdata_current_positions`

Existing file inputs:

- `JStockGenie - 02.Robinhood Automation\Weekly EQT Basket Routine\20260623\Equity Swing Basket_20260623.csv`
- `JStockGenie - 02.Robinhood Automation\Weekly ETF Basket Routine\20260621\Custom Growth Basket_20260621.csv`
- `JStockGenie - 02.Robinhood Automation\Weekly ETF Basket Routine\20260621\Custom Dividend Basket_20260621.csv`
- `JStockGenie - 03.Fidelity Analysis\outputs\Fidelity_Recos_ETFs_20260623.csv`

## Account Selection Guidance

- Use `My Investments` ending `1512` for the broadest Robinhood portfolio analysis.
- Use IRA accounts ending `0097` or `9459` when retirement-account exposure is the focus.
- Use `My Agentic` ending `1224` only when analysis may later feed an approved agentic trading routine.
- Keep managed account ending `1832` separate from self-directed recommendations.

## Output Pattern

For each analysis run, create a dated folder:

```text
YYYYMMDD\
  Robinhood_Current_Positions_YYYYMMDD.csv
  Robinhood_Recommendation_Comparison_YYYYMMDD.csv
  Robinhood_Analysis_Summary_YYYYMMDD.md
```

## Recommendation Buckets

- `HOLD`: current holding aligns with JStockGenie trend, weekly target, or current-position analysis.
- `ADD`: strong JStockGenie signal and enough account-level cash/buying power.
- `TRIM`: current holding is overweight, duplicated, or weakly ranked.
- `SELL_REVIEW`: current holding has weak signal or adverse projection; review manually before action.
- `AVOID_NEW_BUY`: candidate has weak or conflicting projection.
- `OPTIONS_REVIEW`: options exposure requires manual inspection; do not automate.

## Approval Boundary

This folder is analysis-only. Any live Robinhood order must move through the separate Robinhood automation workflow and requires explicit confirmation before order placement.
