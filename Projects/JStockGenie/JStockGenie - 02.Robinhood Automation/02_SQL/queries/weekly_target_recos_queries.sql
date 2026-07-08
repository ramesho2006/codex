-- Weekly 1%-3% target-band recommendation review queries.
-- These are decision-support outputs, not guaranteed profit instructions.

-- Agentic equity swing candidates.
SELECT
  target_rank,
  scrip,
  direction,
  current_price,
  target_profit_pct,
  weeklyized_target_profit_pct,
  expected_return_pct,
  upward_probability_pct,
  downward_probability_pct,
  risk_reward_ratio,
  projection_confidence_score,
  news_swing_signal,
  news_sentiment_score,
  news_catalyst_score,
  news_risk_score,
  news_top_headline,
  target_band_status,
  notes
FROM jstockdata_reco_weekly_target_recos
WHERE reco_category = 'EQT'
ORDER BY target_rank;

-- ETF basket candidates.
SELECT
  target_rank,
  scrip,
  direction,
  current_price,
  target_profit_pct,
  weeklyized_target_profit_pct,
  expected_return_pct,
  upward_probability_pct,
  downward_probability_pct,
  risk_reward_ratio,
  projection_confidence_score,
  news_swing_signal,
  news_sentiment_score,
  news_catalyst_score,
  news_risk_score,
  news_top_headline,
  target_band_status,
  notes
FROM jstockdata_reco_weekly_target_recos
WHERE reco_category = 'ETF'
ORDER BY target_rank;

-- Manual-only options candidates for non-Agentic accounts.
-- Verify live bid/ask, volume/open interest, assignment risk, and account approval level before placing any order.
SELECT
  target_rank,
  scrip,
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
  news_options_signal,
  news_sentiment_score,
  news_catalyst_score,
  news_risk_score,
  news_top_headline,
  target_band_status,
  notes
FROM jstockdata_reco_weekly_target_recos
WHERE reco_category = 'OPTIONS'
  AND account_scope = 'Non-Agentic Manual Only'
ORDER BY target_rank;

-- Current news catalyst overlay for the active top-1000 universe.
SELECT
  n.scrip,
  s.RecoUniverseRank,
  n.news_count,
  n.swing_news_signal,
  n.options_news_signal,
  n.news_sentiment_score,
  n.catalyst_score,
  n.news_risk_score,
  n.binary_event_risk_flag,
  n.top_headline,
  n.top_url
FROM jstockdata_reco_news_signal n
JOIN jstockdata_scrips s ON s.Scrip = n.scrip
WHERE s.RecoUniverseStatus = 'KEEP'
  AND s.RecoUniverseRank <= 1000
  AND n.swing_news_signal <> 'NO_RECENT_NEWS'
ORDER BY ABS(n.news_sentiment_score) DESC, n.catalyst_score DESC, n.news_risk_score DESC, s.RecoUniverseRank;
