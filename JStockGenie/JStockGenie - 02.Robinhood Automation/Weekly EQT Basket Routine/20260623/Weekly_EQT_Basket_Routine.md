# Weekly EQT Basket Routine

Routine name: Weekly EQT Basket Routine

Use this routine when asked to run the weekly JStockGenie equity swing basket process for the Robinhood Agentic account.

## Purpose

Create and maintain a small equity swing basket using JStockGenie trend-model outputs, Robinhood Agentic account positions, and weekly trade-journal tracking.

Target account:

- Robinhood account: My Agentic
- Account ending: 1224
- Automation status: equity order automation allowed

## Capital Plan

This routine is designed for a starting capital allocation of 1000 to 1500 USD.

Suggested position sizing:

- 1000 USD account: 4 to 5 positions, about 20% to 25% each.
- 1500 USD account: 5 to 6 positions, about 16% to 20% each.
- Keep 5% to 10% cash reserve when possible.
- Use fractional market orders only during regular market hours, or marketable limit orders when exact share sizing is needed.

## MySQL Inputs

Use these JStockGenie tables:

- jstockdata_hatrend
- jstockdata_hatrend_extend
- jstockdata_harecent
- jstockdata_harecent_extend
- jstockdata_reco_trade
- jstockdata_reco_backtest
- jstockdata_reco_basket_current
- jstockdata_reco_basket_actions
- jstockdata_reco_basket_positions
- jstockdata_reco_basket_reconciliation
- jstockdata_reco_basket_summary

Use these routines when a fresh refresh is requested or approved:

- reco_weekly_projection_refresh
- reco_projection_refresh
- reco_projection_enrich_outputs
- reco_trade
- reco_backtest
- reco_basket_refresh

Do not run mutating routines silently. If the user asks for a fresh weekly run, confirm whether to refresh the reco tables or use the latest available outputs.

## Weekly Steps

1. Pull current Robinhood Agentic account portfolio, buying power, open equity positions, and recent equity orders.
2. Pull the current JStockGenie swing candidates from jstockdata_reco_trade and supporting backtest rows from jstockdata_reco_backtest.
3. Join candidates to jstockdata_harecent and jstockdata_harecent_extend for daily and weekly HA trend context.
4. Score candidates using:
   - trade_signal = BUY
   - daily/weekly trend alignment
   - SMADeltaTrend = UP
   - HA trend and recent combined signal
   - upward_projection_pct
   - upward_probability_pct
   - downward_projection_pct
   - downward_probability_pct
   - expected_return_pct
   - risk_reward_ratio
   - projection_confidence_score
   - backtest win rate
   - backtest total return
   - average trade return
   - worst trade drawdown
   - days since recent signal
5. Build a weekly swing basket of 4 to 6 stocks depending on account value.
6. Compare the target basket with current Agentic positions:
   - HOLD positions still in the target basket with valid BUY/HOLD signals.
   - SELL positions no longer in the target basket or with failed trend confirmation.
   - BUY new target names using available buying power after planned sells.
7. Check Robinhood tradability for all proposed symbols.
8. Prepare order reviews for proposed buys and sells.
9. Place orders only after explicit user confirmation of final symbol, side, amount or quantity, order type, and account.
10. Update the weekly trade journal and current-position tracker after fills are confirmed.

## Suggested Sell Rules

Sell or reduce a position when any of these are true:

- Symbol drops out of the weekly target basket.
- Daily and weekly combined signals are both SELL.
- SMADeltaTrend turns DOWN on both daily and weekly views.
- Position has hit a user-defined stop-loss.
- Position has reached a user-defined profit target and the signal is weakening.

Default review thresholds:

- Stop-loss review: -6% to -8% from average cost.
- Profit-lock review: +10% to +15% from average cost.

These are review triggers, not automatic order instructions.

## Suggested Buy Rules

Buy only when all are true:

- Candidate is in the weekly target swing basket.
- Robinhood marks the symbol as tradable in the Agentic account.
- Account has sufficient buying power.
- The proposed allocation respects max position size.
- User explicitly confirms the reviewed order.

## Output Files

For each run, create a dated folder:

Weekly EQT Basket Routine/YYYYMMDD

Create or update these files:

- Equity Swing Basket_YYYYMMDD.csv
- Equity Swing Proposed Trades_YYYYMMDD.csv
- Equity Swing Current Positions_YYYYMMDD.csv
- Equity Swing Weekly Trade Journal_YYYYMMDD.csv
- Equity Swing Weekly Summary_YYYYMMDD.md

## Projection Fields

Use these enriched recommendation fields when available:

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

For short-term swing trades, prefer 5 to 20 trading-day projection horizons.

## Guardrails

- Never place a live Robinhood order without explicit user confirmation.
- Review orders before placing unless the user explicitly asks to skip review.
- Use account 1224 only for this routine unless the user changes the target account.
- Ignore AABAZZ in all activity and reporting.
- This routine is decision support and trade execution assistance, not financial advice.
