# Weekly Trading Operations Runbook

Updated: 2026-07-05

## Weekly Sequence

1. Upload latest EOD data.
2. Run Java Trend model.
3. Let Java run the SQL reco wrapper, or check whether it already ran recently.
4. Validate SQL freshness and output tables.
5. Generate Weekly ETF Basket Routine output.
6. Generate Weekly EQT Basket Routine output for the Agentic account.
7. Generate Weekly Options Recos for non-Agentic/manual accounts.
8. Review Agentic account positions, buying power, open orders, and cash buffer.
9. Prepare Agentic EQT proposed trades as review-only.
10. Place Agentic orders only after explicit user confirmation.
11. User manually reviews/places ETF and options trades in non-Agentic accounts.
12. Update the Agentic trading journal after fills/funds/position changes.

## 1. EOD Data Upload

- Upload the latest Friday EOD data.
- Confirm raw data is available before running Java.

## 2. Java Trend Model

Run the Java Trend model as usual.

The Java reco path now includes:

```sql
CALL reco_weekly_projection_refresh();
```

That wrapper runs:

1. `reco_backtest`
2. `reco_trade`
3. `reco_invest`
4. `reco_options`
5. `reco_projection_refresh`
6. `reco_projection_enrich_outputs`
7. `reco_momentum_refresh`
8. `reco_basket_refresh`
9. `reco_weekly_target_refresh`

Java then runs Yahoo options premium enrichment.

## 3. Check SQL Tables

Before running basket routines, check the reco routine timestamp:

```sql
SELECT routine_name, last_run_at, last_status, run_count
FROM jstockdata_reco_routine_runlog
WHERE routine_name = 'reco_weekly_projection_refresh';
```

- If `last_run_at` is within 1 day, do not rerun SQL routines. Use the current reco tables.
- If `last_run_at` is more than 2 days old, ask before running `CALL reco_weekly_projection_refresh();`.
- If the run log is missing or unclear, also check `MAX(updated_at)` from `jstockdata_reco_basket_current` and ask before any SQL refresh.

Check these after Java completes:

- `jstockdata_reco_backtest`
- `jstockdata_reco_trade`
- `jstockdata_reco_invest`
- `jstockdata_reco_options`
- `jstockdata_reco_projection`
- `jstockdata_momentum_signal`
- `jstockdata_reco_basket_current`
- `jstockdata_reco_basket_actions`
- `jstockdata_reco_weekly_target_recos`

Quick validation:

```sql
SELECT COUNT(*) FROM jstockdata_reco_projection;
SELECT COUNT(*), SUM(upward_projection_pct IS NOT NULL) FROM jstockdata_reco_trade;
SELECT COUNT(*), SUM(underlying_upward_projection_pct IS NOT NULL) FROM jstockdata_reco_options;
SELECT frequency, momentum_direction, momentum_phase, COUNT(*)
FROM jstockdata_momentum_signal
GROUP BY frequency, momentum_direction, momentum_phase;
SELECT reco_category, target_band_status, COUNT(*)
FROM jstockdata_reco_weekly_target_recos
GROUP BY reco_category, target_band_status;
```

Momentum guardrail:

- Use `jstockdata_momentum_signal` as confirmation beside `Combined_Signal`.
- Do not replace `Combined_Signal`; momentum explains whether the signal is early, accelerating, mature, weakening, or reversal-risk.
- For new EQT/ETF buys, prefer `momentum_direction = 'BULLISH'` with `momentum_phase IN ('EARLY', 'ACCELERATING')`, or accept `MATURE` only with smaller sizing/profit-lock discipline.
- Avoid or reduce candidates with `momentum_phase = 'REVERSAL_RISK'` unless there is a specific override reason.
- For options, align strategy direction with momentum: bullish momentum favors cash-secured puts; bearish/weakening momentum favors covered-call review only when shares are already held.

Target-return guardrail:

- Use `jstockdata_reco_weekly_target_recos` as the weekly target review surface for EQT, ETF, and manual options candidates.
- The 1% to 3% weekly objective is a modeled target band, not a guaranteed profit.
- Prefer `target_band_status = 'IN_BAND'`; use `ABOVE_BAND` only when probability, downside, and risk/reward are strong enough and position size remains conservative.
- For options, use `weeklyized_target_profit_pct` for the 1% to 3% weekly target and verify the live option chain before any manual order.

## 4. Robinhood Agentic Automation

Use:

- Weekly EQT Basket Routine

Purpose:

- short-term swing trades, days to a few weeks

Steps:

1. Pull Agentic portfolio, cash, buying power, current positions, and open orders.
2. Confirm the 25% cash buffer target.
3. Compare positions against EQT target-band rows:
   - `jstockdata_reco_weekly_target_recos.reco_category = 'EQT'`
   - join/check `jstockdata_momentum_signal`
   - use `Combined_Signal` and momentum together
4. Prepare SELL candidates first:
   - no longer in EQT target basket
   - weak or SELL `Combined_Signal`
   - bearish/weakening/reversal-risk momentum
   - poor projection confidence or downside risk
5. Prepare BUY candidates:
   - strongest EQT target-band rows
   - target 1% to 3% weekly review band
   - positive `Combined_Signal`
   - bullish or improving momentum
   - allocation preserves cash buffer
6. Check Robinhood tradability.
7. Create proposed trades and summary files as review-only.
8. Review orders with the user.
9. Place orders only after explicit approval.
10. Update current positions, proposed trades, weekly journal, and weekly summary after fills.

Sizing rule:

- Keep a 25% cash buffer in the Agentic account for weekly BUY/SELL rotations unless the user explicitly overrides it.

## 5. Manual Trades For Other Robinhood Accounts

Use:

- Weekly ETF Basket Routine
- Manual-only weekly options recommendations from `jstockdata_reco_weekly_target_recos`

Purpose:

- longer-term investments, weeks to a few months

Steps:

1. Review account positions manually.
2. Generate ETF growth/dividend basket output.
3. Compare holdings to ETF target-band rows and ETF growth/dividend baskets.
4. Use `Combined_Signal` plus `jstockdata_momentum_signal` for timing:
   - add/hold when signal and momentum align
   - wait when signal is positive but momentum is mature or reversal-risk
   - trim/watch when signal weakens and momentum turns bearish
5. Use projection fields for conviction:
   - `upward_probability_pct`
   - `upward_projection_pct`
   - `downward_probability_pct`
   - `downward_projection_pct`
   - `risk_reward_ratio`
   - `projection_confidence_score`
6. For options, only use rows where `reco_category = 'OPTIONS'` and `account_scope = 'Non-Agentic Manual Only'`.
7. For options, require live chain review:
   - bid/ask spread
   - volume/open interest
   - estimated collateral or covered-share requirement
   - assignment risk
   - account approval level
8. Place trades manually in Robinhood after review.

## Notes

- Agentic account can be automated after explicit approval.
- Other accounts are analysis/manual execution only.
- `AABAZZ` remains ignored in reporting and activity.
- Momentum and target-return fields are decision-support filters; they do not guarantee weekly profit.
