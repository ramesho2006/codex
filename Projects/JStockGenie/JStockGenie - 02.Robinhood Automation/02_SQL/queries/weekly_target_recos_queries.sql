-- Weekly 1%-3% target-band recommendation review queries.
-- These are decision-support outputs, not guaranteed profit instructions.

-- Agentic equity swing candidates.
SELECT
  target_rank,
  symbol,
  direction,
  current_price,
  target_profit_pct,
  weeklyized_target_profit_pct,
  expected_return_pct,
  upward_probability_pct,
  downward_probability_pct,
  risk_reward_ratio,
  projection_confidence_score,
  target_band_status,
  notes
FROM jstockdata_reco_weekly_target_recos
WHERE reco_category = 'EQT'
ORDER BY target_rank;

-- ETF basket candidates.
SELECT
  target_rank,
  symbol,
  direction,
  current_price,
  target_profit_pct,
  weeklyized_target_profit_pct,
  expected_return_pct,
  upward_probability_pct,
  downward_probability_pct,
  risk_reward_ratio,
  projection_confidence_score,
  target_band_status,
  notes
FROM jstockdata_reco_weekly_target_recos
WHERE reco_category = 'ETF'
ORDER BY target_rank;

-- Manual-only options candidates for non-Agentic accounts.
-- Verify live bid/ask, volume/open interest, assignment risk, and account approval level before placing any order.
SELECT
  target_rank,
  symbol,
  direction,
  option_trade,
  option_type,
  option_side,
  strike_price,
  exp_date,
  dte,
  premium,
  premium_roi_pct,
  weeklyized_target_profit_pct,
  current_price,
  recommendation_score,
  target_band_status,
  notes
FROM jstockdata_reco_weekly_target_recos
WHERE reco_category = 'OPTIONS'
  AND account_scope = 'Non-Agentic Manual Only'
ORDER BY target_rank;
