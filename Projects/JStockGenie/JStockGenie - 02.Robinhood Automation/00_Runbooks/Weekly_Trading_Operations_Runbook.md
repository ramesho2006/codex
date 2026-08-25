# Weekly Trading Operations Runbook

Updated: 2026-07-05

## Standing Instructions

- Log every user prompt for this chat to `D:\Codex\Prompts\JStockGenie - 02.Robinhood Automation v2.txt` using `YYYYMMDD HH:MM` followed by a divider line.
- Before running weekly routines, refer to `README.md`, this runbook, and `Reco_SQL_Refresh_Runbook.md`.
- Update README and runbooks whenever SQL routine order, universe ranking, news overlay, reco filters, or trading workflow changes.

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
12. Run midweek Agentic profit-lock review after Monday fills.
13. Update the Agentic trading journal after fills/funds/position changes.

## 1. EOD Data Upload

- Upload the latest Friday EOD data.
- Confirm raw data is available before running Java.

## 2. Java Trend Model

Run the Java Trend model as usual.

The Java reco path now includes:

```sql
CALL reco_weekly_master_refresh();
```

That wrapper runs:

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
11. `reco_weekly_target_refresh`

The universe refresh updates `jstockdata_scrips.RecoUniverseStatus` and `RecoUniverseRank` before recommendation tables are rebuilt. Reco routines should only use rows where `RecoUniverseStatus = 'KEEP'` and `RecoUniverseRank <= 1000`. The news signal refresh scores already-fetched headlines; fetch fresh news first with `05_Tools/reco_news_fetcher.py` when an API key is configured. Predictive direction refresh then builds major pivot history and latest direction/weekly-verdict rows for screening.

Java then runs Yahoo options premium enrichment.

## 3. Check SQL Tables

Before running weekly recommendation routines, check the reco routine timestamp:

```sql
SELECT routine_name, last_run_at, last_status, run_count
FROM jstockdata_reco_routine_runlog
WHERE routine_name = 'reco_weekly_master_refresh';
```

- If `last_run_at` is within 1 day, do not rerun SQL routines. Use the current reco tables.
- If `last_run_at` is more than 2 days old, ask before running `CALL reco_weekly_master_refresh();`.
- If the run log is missing or unclear, also check row freshness in `jstockdata_reco_weekly_target_recos` and `jstockdata_current_positions` before any SQL refresh or position analysis.

Check these after Java completes:

- `jstockdata_reco_backtest`
- `jstockdata_reco_major_pivots`
- `jstockdata_reco_predictive_direction`
- `jstockdata_reco_trade`
- `jstockdata_reco_invest`
- `jstockdata_reco_options`
- `jstockdata_reco_projection`
- `jstockdata_reco_momentum_signal`
- `jstockdata_reco_weekly_target_recos`
- `jstockdata_current_positions`

Quick validation:

```sql
SELECT COUNT(*) FROM jstockdata_reco_projection;
SELECT COUNT(*), SUM(upward_projection_pct IS NOT NULL) FROM jstockdata_reco_trade;
SELECT COUNT(*), SUM(underlying_upward_projection_pct IS NOT NULL) FROM jstockdata_reco_options;
SELECT frequency, momentum_direction, momentum_phase, COUNT(*)
FROM jstockdata_reco_momentum_signal
GROUP BY frequency, momentum_direction, momentum_phase;
SELECT reco_category, target_band_status, COUNT(*)
FROM jstockdata_reco_weekly_target_recos
GROUP BY reco_category, target_band_status;
```

Momentum guardrail:

- Use `jstockdata_reco_momentum_signal` as confirmation beside `Combined_Signal`.
- Do not replace `Combined_Signal`; momentum explains whether the signal is early, accelerating, mature, weakening, or reversal-risk.
- For new EQT/ETF buys, prefer `momentum_direction = 'BULLISH'` with `momentum_phase IN ('EARLY', 'BULLISH_ACCELERATING')`, or accept `MATURE` only with smaller sizing/profit-lock discipline.
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
   - join/check `jstockdata_reco_momentum_signal`
   - use `Combined_Signal` and momentum together
4. Prepare SELL candidates first:
   - no longer in EQT target basket
   - weak or SELL `Combined_Signal`
   - bearish/weakening/reversal-risk momentum
   - poor projection confidence or downside risk
5. Prepare BUY candidates:
   - strongest EQT target-band rows
   - target at least 3% weekly upside with high confidence
   - positive `Combined_Signal`
   - bullish or improving momentum
   - allocation preserves cash buffer
   - maximum four active Agentic positions; prefer four or fewer excellent/fusion-aligned setups over broader diversification
   - stop-loss risk should not exceed -1% from entry for each individual position
   - skip the week when the top candidates are not strongly aligned; no trade is better than forcing average setups
6. Check Robinhood tradability.
7. Create proposed trades and summary files as review-only.
8. Review orders with the user.
9. Place orders only after explicit approval.
10. Update current positions, proposed trades, weekly journal, and weekly summary after fills.

Sizing rule:

- Keep a 25% cash buffer in the Agentic account for weekly BUY/SELL rotations unless the user explicitly overrides it.
- Use a concentrated Agentic basket: maximum four active positions unless the user explicitly overrides it. If more than four candidates qualify, rank by fusion score, weekly target confidence, risk flag, liquidity/spread quality, and profit-lock fit, then keep only the top four.
- Require very high conviction for weekly Agentic trades. Treat "sure shot" as a strict filter, not a guarantee: strong fusion verdict, bullish direction, at least 3% weekly upside target, max -1% stop-loss risk, clean risk flag, acceptable liquidity/spread, and no major negative catalyst. If this standard is not met, recommend holding cash and skipping that week.

Golden Trade Rule:

- Pick four super candidates with high confidence for at least 3% full-basket profit within the week.
- +3% profit target is for the full `My Agentic` basket level.
- -1% stop loss is for each individual position only.
- If any one position hits -1%, prepare an exit review for that position.
- If the full basket hits +3%, prepare full basket profit booking.
- Exit all if needed and reset to cash.
- If four excellent candidates are not available, do not trade that week; wait for the next weekly setup.
- Golden Trade Alert: monitor `My Agentic` P/L during market days, preferably 10:30 AM, 12:30 PM, and 2:30 PM Central. Apply the Golden Trade Rule, generate alerts, and record every snapshot in `jstockdata_agentic_pl_log`.
- Golden Trade Action: after an alert, get explicit user confirmation and place only the approved Robinhood orders. Do not place trades automatically from a scheduled monitor unless the user has explicitly confirmed the specific order action in the active conversation.

Golden Trade terms:

- Golden Trade Rule - basic rules for P/L booking.
- Golden Trade Alert - checking and applying the Golden Trade Rule and generating alerts.
- Golden Trade Action - getting confirmation and placing orders.

Profit-lock rule:

- Check Agentic positions at least once midweek after Monday fills, and again before Friday close when practical.
- Calculate unrealized P/L % by position from live Robinhood quantity, average cost, and current quote.
- Also calculate Monday-basket P/L % for positions opened or added during the current week.
- Primary rule: `My Agentic` targets about 3% average weekly profit at the basket level. If the total current-week basket P/L reaches +3% at any point during the week, prepare a full basket profit/loss booking plan for user confirmation, then stop trading that basket and wait for the next weekly rotation.
- Stop-loss rule: if any individual Agentic position reaches -1% unrealized P/L, prepare a SELL/exit review immediately. The -1% stop-loss rule is per position, not for the full basket. Do not allow positions intended for weekly trading to drift to -3% without a specific user-approved override.
- A full exit and clean reset is allowed after profit booking, when risk rises, or when the next weekly setup quality is not highly favorable. It is acceptable for `My Agentic` to sit mostly or fully in cash until a better weekly basket appears.
- If the total basket is below +3% but an individual position is up 3% to 5%, prepare a SELL/trim review:
  - sell 50% when fusion verdict remains bullish but momentum is mature or weakening
  - sell 100% when fusion/quant is weak, momentum is bearish, or the position was intended as a short 1-2 week profit capture
  - use a trailing stop or manual review if the user wants to let a strong winner run
- If the overall Monday basket is up 3% or more while individual gains are mixed, prioritize full basket profit/loss booking instead of waiting for each individual position to reach its own target.
- Do not auto-sell for profit lock without explicit user confirmation.

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
4. Use `Combined_Signal` plus `jstockdata_reco_momentum_signal` for timing:
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
