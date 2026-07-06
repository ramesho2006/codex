CREATE DEFINER=`admin`@`%` PROCEDURE `reco_projection_enrich_outputs`()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_projection_best;
    CREATE TEMPORARY TABLE tmp_projection_best AS
    SELECT p.*
    FROM `jstockdata_reco_projection` p
    JOIN (
        SELECT symbol, frequency, signal_direction, horizon_bars, MAX(confidence_score) AS max_confidence
        FROM `jstockdata_reco_projection`
        GROUP BY symbol, frequency, signal_direction, horizon_bars
    ) best
      ON best.symbol = p.symbol
     AND best.frequency = p.frequency
     AND best.signal_direction = p.signal_direction
     AND best.horizon_bars = p.horizon_bars
     AND best.max_confidence = p.confidence_score;
    ALTER TABLE tmp_projection_best
      ADD INDEX ix_best (symbol, frequency, signal_direction, horizon_bars),
      ADD INDEX ix_best_projection (projection_id);

    UPDATE `jstockdata_reco_trade` r
    JOIN tmp_projection_best p
      ON p.symbol = r.symbol
     AND p.frequency = r.frequency
     AND p.signal_direction = r.trade_signal
     AND p.horizon_bars = CASE WHEN r.frequency = 'DAILY' THEN 10 ELSE 4 END
    SET r.trading_horizon_days = p.horizon_days,
        r.trading_horizon_weeks = p.horizon_weeks,
        r.upward_projection_pct = p.upward_projection_pct,
        r.upward_probability_pct = p.upward_probability_pct,
        r.downward_projection_pct = p.downward_projection_pct,
        r.downward_probability_pct = p.downward_probability_pct,
        r.expected_return_pct = p.expected_return_pct,
        r.risk_reward_ratio = p.risk_reward_ratio,
        r.projection_sample_size = p.sample_size,
        r.projection_confidence_score = p.confidence_score;

    UPDATE `jstockdata_reco_backtest` r
    JOIN tmp_projection_best p
      ON p.symbol = r.symbol
     AND p.frequency = r.frequency
     AND p.signal_direction = r.trade_signal
     AND p.horizon_bars = CASE WHEN r.frequency = 'DAILY' THEN 10 ELSE 4 END
    SET r.trading_horizon_days = p.horizon_days,
        r.trading_horizon_weeks = p.horizon_weeks,
        r.upward_projection_pct = p.upward_projection_pct,
        r.upward_probability_pct = p.upward_probability_pct,
        r.downward_projection_pct = p.downward_projection_pct,
        r.downward_probability_pct = p.downward_probability_pct,
        r.expected_return_pct = p.expected_return_pct,
        r.risk_reward_ratio = p.risk_reward_ratio,
        r.projection_sample_size = p.sample_size,
        r.projection_confidence_score = p.confidence_score;

    UPDATE `jstockdata_reco_invest` r
    JOIN tmp_projection_best p
      ON p.symbol = r.symbol
     AND p.frequency = 'WEEKLY'
     AND p.signal_direction = r.trade_signal
     AND p.horizon_bars = 8
    SET r.trading_horizon_days = p.horizon_days,
        r.trading_horizon_weeks = p.horizon_weeks,
        r.upward_projection_pct = p.upward_projection_pct,
        r.upward_probability_pct = p.upward_probability_pct,
        r.downward_projection_pct = p.downward_projection_pct,
        r.downward_probability_pct = p.downward_probability_pct,
        r.expected_return_pct = p.expected_return_pct,
        r.risk_reward_ratio = p.risk_reward_ratio,
        r.projection_sample_size = p.sample_size,
        r.projection_confidence_score = p.confidence_score;

    DROP TEMPORARY TABLE IF EXISTS tmp_option_projection_match;
    CREATE TEMPORARY TABLE tmp_option_projection_match AS
    SELECT
        o.opportunity_id,
        p.projection_id,
        ABS(p.horizon_days - o.dte) AS dte_distance,
        p.confidence_score
    FROM `jstockdata_reco_options` o
    JOIN tmp_projection_best p
      ON p.symbol = o.scrip
     AND p.signal_direction = o.direction
     AND p.frequency = CASE WHEN o.dte <= 30 THEN 'DAILY' ELSE 'WEEKLY' END
    WHERE o.dte IS NOT NULL;
    ALTER TABLE tmp_option_projection_match ADD INDEX ix_match (opportunity_id, dte_distance, confidence_score);

    DROP TEMPORARY TABLE IF EXISTS tmp_option_projection_nearest;
    CREATE TEMPORARY TABLE tmp_option_projection_nearest AS
    SELECT opportunity_id, MIN(dte_distance) AS min_distance
    FROM tmp_option_projection_match
    GROUP BY opportunity_id;
    ALTER TABLE tmp_option_projection_nearest ADD PRIMARY KEY (opportunity_id);

    DROP TEMPORARY TABLE IF EXISTS tmp_option_projection_best;
    CREATE TEMPORARY TABLE tmp_option_projection_best AS
    SELECT m.opportunity_id, MIN(m.projection_id) AS projection_id
    FROM tmp_option_projection_match m
    JOIN tmp_option_projection_nearest n
      ON n.opportunity_id = m.opportunity_id
     AND n.min_distance = m.dte_distance
    GROUP BY m.opportunity_id;
    ALTER TABLE tmp_option_projection_best ADD PRIMARY KEY (opportunity_id);

    UPDATE `jstockdata_reco_options` o
    JOIN tmp_option_projection_best b ON b.opportunity_id = o.opportunity_id
    JOIN `jstockdata_reco_projection` p ON p.projection_id = b.projection_id
    SET o.underlying_trading_horizon_days = p.horizon_days,
        o.underlying_upward_projection_pct = p.upward_projection_pct,
        o.underlying_upward_probability_pct = p.upward_probability_pct,
        o.underlying_downward_projection_pct = p.downward_projection_pct,
        o.underlying_downward_probability_pct = p.downward_probability_pct,
        o.expected_underlying_move_pct = CASE WHEN o.direction = 'BUY' THEN p.upward_projection_pct ELSE p.downward_projection_pct END,
        o.underlying_projection_confidence_score = p.confidence_score,
        o.underlying_projection_sample_size = p.sample_size;

    DROP TEMPORARY TABLE IF EXISTS tmp_projection_best;
    DROP TEMPORARY TABLE IF EXISTS tmp_option_projection_match;
    DROP TEMPORARY TABLE IF EXISTS tmp_option_projection_nearest;
    DROP TEMPORARY TABLE IF EXISTS tmp_option_projection_best;
END