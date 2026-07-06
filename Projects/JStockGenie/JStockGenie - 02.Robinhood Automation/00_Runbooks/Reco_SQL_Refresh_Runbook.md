# Weekly Reco Projection Upgrade Checklist

Created: 2026-06-23
Updated: 2026-07-05

Use this after Friday EOD data load and Java trend model completion.

## 1. Reco Routines To Run Weekly

The Java Trend model now runs this wrapper automatically through `JStockDataRunRecommendations(true)`:

```sql
CALL reco_weekly_projection_refresh();
```

It runs:

1. reco_backtest
2. reco_trade
3. reco_invest
4. reco_options
5. reco_projection_refresh
6. reco_projection_enrich_outputs
7. reco_momentum_refresh
8. reco_basket_refresh
9. reco_weekly_target_refresh

The wrapper refreshes projection fields in:

- jstockdata_reco_backtest
- jstockdata_reco_trade
- jstockdata_reco_invest
- jstockdata_reco_options

The wrapper also refreshes the weekly 1% to 3% target review table:

- jstockdata_reco_weekly_target_recos

The wrapper also refreshes the momentum confirmation table:

- jstockdata_momentum_signal

Manual SQL use is only needed for troubleshooting or ad hoc refreshes. The normal weekly process should be Java-driven.

## 1B. Reco Routine Freshness Rule

The weekly wrapper records its run timestamp in:

```sql
jstockdata_reco_routine_runlog
```

Check freshness before running Weekly ETF Basket Routine or Weekly EQT Basket Routine:

```sql
SELECT routine_name, last_run_at, last_status, last_message
FROM jstockdata_reco_routine_runlog
WHERE routine_name IN (
  'reco_weekly_projection_refresh',
  'reco_backtest',
  'reco_trade',
  'reco_invest',
  'reco_options',
  'reco_projection_refresh',
  'reco_projection_enrich_outputs',
  'reco_momentum_refresh',
  'reco_basket_refresh',
  'reco_weekly_target_refresh'
)
ORDER BY routine_name;
```

- Within 1 day: do not rerun SQL routines; generate basket recommendations from current tables.
- More than 2 days old: ask for confirmation before running `CALL reco_weekly_projection_refresh();`.
- Between 1 and 2 days: prefer using current tables unless the user explicitly asks for a refresh.

## 1A. Weekly Java Flow

After EOD data upload, run the Java Trend model. The Trend/Reco Java path now includes:

1. Trend CSV generation/import
2. Summary import
3. `CALL reco_weekly_projection_refresh()`
4. Momentum confirmation refresh
5. Yahoo options premium enrichment
6. Updated `jstockdata_reco_*` and `jstockdata_momentum_signal` tables

Projection source table:

- jstockdata_reco_projection
- jstockdata_reco_weekly_target_recos
- jstockdata_momentum_signal

## 2. Weekly Basket Routines

Short-term swing, days to a few weeks:

- perform Weekly EQT Basket Routine
- use `jstockdata_reco_weekly_target_recos` first, with `reco_category = 'EQT'`
- use `jstockdata_reco_trade` as the supporting detail table
- use `jstockdata_momentum_signal` as momentum confirmation beside `Combined_Signal`
- prioritize 5 to 20 trading-day projection horizons
- prefer high upward_probability_pct, strong expected_return_pct, favorable risk_reward_ratio, and acceptable downward_projection_pct
- prefer bullish momentum with EARLY or ACCELERATING phase for new buys
- treat MATURE as hold/profit-lock review and REVERSAL_RISK as avoid/reduce review
- target 1% to 3% weekly profit as a review band, not as a guaranteed outcome

Longer-term investment, weeks to a few months:

- perform Weekly ETF Basket Routine
- use `jstockdata_reco_weekly_target_recos` first, with `reco_category = 'ETF'`
- use ETF common-holding overlap plus JStockGenie projection fields
- use weekly momentum to avoid adding ETF exposure into MATURE or REVERSAL_RISK phases
- prioritize 4 to 16 week projection horizons
- prefer higher projection_confidence_score and lower downward_probability_pct
- prefer `target_band_status = 'IN_BAND'`

Manual weekly options, non-Agentic accounts only:

- use `jstockdata_reco_weekly_target_recos` with `reco_category = 'OPTIONS'`
- use `weeklyized_target_profit_pct` for the 1% to 3% weekly target band
- use momentum to align option strategy direction:
  - bullish momentum: cash-secured put candidates may be considered
  - bearish or weakening momentum: covered-call review only if shares are already held
  - reversal-risk momentum: avoid new premium-selling exposure unless explicitly overridden
- place no automated orders; the user manually reviews and places any options trades
- prefer covered calls or cash-secured puts, and verify live bid/ask spread, volume/open interest, assignment risk, and account-specific approval level

## 3. Robinhood Agentic Account Trade Automation

Target account:

- My Agentic, ending 1224

Weekly process:

1. Pull buying power, current positions, and open orders.
2. Compare current positions with Weekly EQT Basket Routine target basket.
3. Prepare SELL candidates first:
   - no longer in target basket
   - weak daily/weekly signals
   - poor projection confidence
   - downside projection exceeds tolerance
4. Prepare BUY candidates from highest-ranked EQT basket names.
   - Start with `jstockdata_reco_weekly_target_recos` where `reco_category = 'EQT'`.
   - Prefer `target_band_status = 'IN_BAND'`; use `ABOVE_BAND` only with conservative sizing.
   - Confirm `Combined_Signal` and `jstockdata_momentum_signal` agree or document the mismatch.
5. Check Robinhood tradability.
6. Review each order.
7. Place real orders only after explicit user confirmation.
8. Update:
   - current positions CSV
   - proposed trades CSV
   - weekly trade journal
   - weekly summary

Cash buffer:

- Keep 25% of the Agentic account as cash for weekly BUY/SELL rotations unless explicitly overridden.

## 4. Manual Investing Steps For Other Robinhood Accounts

Use analysis only. Do not automate trades for non-Agentic accounts.

Weekly process:

1. Review existing positions by account.
2. Compare holdings with Weekly ETF Basket Routine output.
3. For long-term accounts, prefer gradual rebalancing:
   - keep core ETF exposure
   - add names with strong upward projection and lower downside probability
   - trim names with weak projection or deteriorating weekly trend
4. For retirement accounts, avoid short-term churn unless signals strongly deteriorate.
5. Manually place trades in Robinhood after reviewing tax, options, and account-specific constraints.

## 5. New Projection Fields

Common reco fields:

- trading_horizon_days
- trading_horizon_weeks
- upward_projection_pct
- upward_probability_pct
- downward_projection_pct
- downward_probability_pct
- expected_return_pct
- risk_reward_ratio
- projection_sample_size
- projection_confidence_score

Options-specific fields:

- underlying_trading_horizon_days
- underlying_upward_projection_pct
- underlying_upward_probability_pct
- underlying_downward_projection_pct
- underlying_downward_probability_pct
- expected_underlying_move_pct
- underlying_projection_confidence_score
- underlying_projection_sample_size

## 6. Momentum Fields

Momentum table:

- jstockdata_momentum_signal

Core fields:

- momentum_score
- momentum_direction
- momentum_phase
- momentum_confidence_pct
- momentum_age_bars
- momentum_acceleration
- momentum_exhaustion_score
- momentum_reversal_risk_pct
- predicted_5bar_return_pct
- predicted_10bar_return_pct
- risk_note

Use momentum as a confirmation layer beside Combined_Signal:

- EARLY / ACCELERATING: best new-entry timing.
- MATURE: hold, smaller new allocation, or profit-lock review.
- WEAKENING / REVERSAL_RISK: avoid new buys, consider reduce/trim review.
- NEUTRAL: wait for stronger confirmation.

## 7. Validation Query

```sql
SELECT COUNT(*) FROM jstockdata_reco_projection;

SELECT COUNT(*), SUM(upward_projection_pct IS NOT NULL)
FROM jstockdata_reco_trade;

SELECT COUNT(*), SUM(underlying_upward_projection_pct IS NOT NULL)
FROM jstockdata_reco_options;

SELECT frequency, momentum_direction, momentum_phase, COUNT(*)
FROM jstockdata_momentum_signal
GROUP BY frequency, momentum_direction, momentum_phase;

SELECT reco_category, target_band_status, COUNT(*)
FROM jstockdata_reco_weekly_target_recos
GROUP BY reco_category, target_band_status;
```
