# JStockGenie Reco Model Projection Upgrade

Created: 2026-06-23
Updated: 2026-07-04

## Goal

Upgrade the JStockGenie recommendation outputs so swing, investment, and options routines can use:

- trading horizon in days or weeks
- positive upward projected move
- probability of upward price movement
- negative downward projected move
- probability of downward price movement

The enhanced outputs should improve:

- Weekly EQT Basket Routine for short-term swing trades
- Weekly ETF Basket Routine for longer-term investment baskets
- options recommendations in jstockdata_reco_options
- weekly target-band recommendations in jstockdata_reco_weekly_target_recos

## Current Signal Foundation

Java source:

D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie\JStockGenie.java

Relevant trend columns:

- SMADeltaTrend
- LODeltaSignal
- Combined_Signal
- Combined_Signal_Ind
- HARSIValue
- HARSIZone

Current combined signal logic:

- BUY when SMADeltaTrend = UP and LODeltaSignal = BUY
- SELL when SMADeltaTrend = DOWN and LODeltaSignal = SELL
- Combined_Signal carries the current state
- Combined_Signal_Ind marks fresh BUY/SELL transitions

Current reco routines:

- reco_backtest
- reco_trade
- reco_invest
- reco_options

## Recommended New Layer

Add an empirical forward-outcome layer based on historical signal rows.

For every scrip, frequency, and signal context, calculate what happened after a BUY or SELL signal over fixed horizons.

Recommended horizons:

- Swing daily: 5, 10, 15, 20 trading days
- Swing weekly: 2, 4, 6, 8 weeks
- Investment weekly/monthly: 4, 8, 12, 16 weeks
- Options: match DTE buckets such as 14, 21, 30, 45 days

## Metrics To Compute

For each signal event and horizon:

- forward_close_return_pct
- max_upside_pct
- max_downside_pct
- close_after_horizon
- max_high_after_signal
- min_low_after_signal
- horizon_bars_observed

Aggregate by scrip/frequency/signal context:

- trading_horizon_days
- trading_horizon_weeks
- upward_projection_pct: median or 60th percentile max_upside_pct
- upward_probability_pct: percent of historical cases with positive close return or target reached
- downward_projection_pct: median or 60th percentile abs(max_downside_pct)
- downward_probability_pct: percent of historical cases with negative close return or stop reached
- expected_return_pct
- risk_reward_ratio
- projection_sample_size
- projection_confidence_score

## Recommended Table Additions

Add these columns to:

- jstockdata_reco_backtest
- jstockdata_reco_trade
- jstockdata_reco_invest

Suggested columns:

- trading_horizon_days INT NULL
- trading_horizon_weeks DECIMAL(8,2) NULL
- upward_projection_pct DECIMAL(10,2) NULL
- upward_probability_pct DECIMAL(6,2) NULL
- downward_projection_pct DECIMAL(10,2) NULL
- downward_probability_pct DECIMAL(6,2) NULL
- expected_return_pct DECIMAL(10,2) NULL
- risk_reward_ratio DECIMAL(10,2) NULL
- projection_sample_size INT NULL
- projection_confidence_score DECIMAL(6,2) NULL

For jstockdata_reco_options, add:

- underlying_trading_horizon_days INT NULL
- underlying_upward_projection_pct DECIMAL(10,2) NULL
- underlying_upward_probability_pct DECIMAL(6,2) NULL
- underlying_downward_projection_pct DECIMAL(10,2) NULL
- underlying_downward_probability_pct DECIMAL(6,2) NULL
- expected_underlying_move_pct DECIMAL(10,2) NULL

## Suggested Supporting Table

Create a reusable projection table:

jstockdata_reco_projection

Suggested grain:

- scrip
- frequency
- assetclass
- signal_direction
- signal_context_key
- horizon_bars
- horizon_days
- sample_size
- upward_projection_pct
- upward_probability_pct
- downward_projection_pct
- downward_probability_pct
- expected_return_pct
- risk_reward_ratio
- confidence_score
- generated_at

This table should be refreshed before reco_trade, reco_invest, reco_options, and weekly target routines consume it.

## Signal Context Key

Use a compact context key so projections are conditional, not generic:

- frequency
- Combined_Signal
- Combined_Signal_Ind
- SMADeltaTrend
- LODeltaSignal
- HARSIZone
- HATrendCorrect

Example:

DAILY|BUY|BUY|UP|BUY|BLUE|GREEN

If sample size is too small for full context, fall back to broader contexts:

1. scrip + frequency + full context
2. scrip + frequency + Combined_Signal + SMADeltaTrend
3. assetclass + frequency + full context
4. assetclass + frequency + Combined_Signal

## Routine Impact

Weekly EQT Basket Routine:

- Use 5 to 20 trading-day projections.
- Prefer high upward probability, strong risk/reward, and low downward probability.
- Use downward_projection_pct for stop review.
- Use upward_projection_pct for profit-lock review.
- Use jstockdata_reco_weekly_target_recos to prioritize modeled 1% to 3% weekly target candidates.
- Treat the 1% to 3% band as a target screen, not a guaranteed profit.

Weekly ETF Basket Routine:

- Use 4 to 16 week projections.
- Prefer higher confidence and smoother downside profile.
- Rank ETF common holdings by ETF overlap plus projection-adjusted trend score.
- Use jstockdata_reco_weekly_target_recos ETF rows when the user asks for weekly ETF basket recommendations.

Options:

- Match option DTE to nearest projection horizon.
- For BUY CALL or SELL PUT, require high upward_probability_pct.
- For BUY PUT or SELL CALL, require high downward_probability_pct.
- Use expected_underlying_move_pct to choose strike moneyness.
- For manual weekly options recommendations, use weeklyized_target_profit_pct from jstockdata_reco_weekly_target_recos and target 1% to 3% weeklyized premium ROI.
- Keep options recommendations non-Agentic/manual-only unless the user gives a separate explicit automation instruction in the future.

## Implementation Order

1. Add jstockdata_reco_projection.
2. Build a reco_projection_refresh routine using historical jstockdata_hatrend and jstockdata_hatrend_extend.
3. Add projection columns to reco output tables.
4. Update reco_backtest to populate projection statistics.
5. Update reco_trade and reco_invest to rank with projection-adjusted score.
6. Update reco_options to map DTE to projection horizon and probability direction.
7. Update Weekly EQT Basket Routine and Weekly ETF Basket Routine outputs to include projection fields.
8. Refresh reco_weekly_target_refresh after projection enrichment to create EQT, ETF, and manual options target-band recos.

## Guardrail

Do not replace current backtest fields. Add projection fields beside them. Existing win rate, total return, average return, and worst trade remain useful validation metrics.
