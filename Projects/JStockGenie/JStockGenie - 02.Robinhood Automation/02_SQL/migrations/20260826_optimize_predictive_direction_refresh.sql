-- Optimize reco_predictive_direction_refresh().
--
-- Main fixes:
-- 1. Scope the refresh to the active KEEP universe instead of every historical scrip.
-- 2. Replace correlated next-pivot lookup with a grouped temp table.
-- 3. Replace correlated weekly-as-of-pivot lookup with grouped temp tables.
-- 4. Mark routine run status when executed directly.

DROP PROCEDURE IF EXISTS `reco_predictive_direction_refresh`;

DELIMITER $$
CREATE PROCEDURE `reco_predictive_direction_refresh`()
BEGIN
  DECLARE v_generated_at DATETIME DEFAULT NOW();
  DECLARE v_min_pivot_move_pct DECIMAL(10,2) DEFAULT 7.00;
  DECLARE v_pivot_window INT DEFAULT 10;
  DECLARE v_current_step VARCHAR(128) DEFAULT 'start';

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    CALL reco_runlog_mark('reco_predictive_direction_refresh', 'FAILED', CONCAT('Failed during ', v_current_step));
    RESIGNAL;
  END;

  SET v_current_step = 'active universe';
  DROP TABLE IF EXISTS tmp_pd_universe;
  CREATE TABLE tmp_pd_universe AS
  SELECT
    s.`Scrip` AS scrip,
    s.`AssetClass` AS assetclass,
    s.`Company Name` AS company_name,
    s.`Rank` AS source_rank,
    s.`RecoUniverseStatus` AS reco_universe_status,
    s.`RecoUniverseRank` AS reco_universe_rank
  FROM `jstockdata_scrips` s
  WHERE s.`Scrip` IS NOT NULL
    AND COALESCE(s.`RecoUniverseStatus`, 'OMIT') = 'KEEP'
    AND COALESCE(s.`RecoUniverseRank`, 999999) <= 1000;

  ALTER TABLE tmp_pd_universe
    ADD PRIMARY KEY (`scrip`),
    ADD KEY `ix_tmp_pd_universe_rank` (`reco_universe_rank`);

  SET v_current_step = 'daily history';
  DROP TABLE IF EXISTS tmp_pd_daily;
  CREATE TABLE tmp_pd_daily AS
  SELECT
    h.`SCRIP` AS scrip,
    u.assetclass,
    h.`DATE` AS signal_date,
    h.`CLOSE` AS close_price,
    h.`volume`,
    h.`HATrendCorrect`,
    h.`HATrendSignal`,
    h.`HAStrongSignal`,
    h.`HAChangePct`,
    h.`HARallySeq`,
    h.`HARallySlope`,
    e.`SMADeltaTrend`,
    e.`HARSIValue`,
    e.`HARSIZone`,
    e.`LODeltaSignal`,
    e.`Combined_Signal`,
    e.`Combined_Signal_Ind`
  FROM tmp_pd_universe u
  JOIN `jstockdata_hatrend` h
    ON h.`SCRIP` = u.scrip
   AND h.`Frequency` = 'DAILY\r'
  LEFT JOIN `jstockdata_hatrend_extend` e
    ON e.`SCRIP` = h.`SCRIP`
   AND e.`DATE` = h.`DATE`
   AND e.`FREQUENCY` = 'DAILY';

  ALTER TABLE tmp_pd_daily
    ADD PRIMARY KEY (`scrip`, `signal_date`),
    ADD KEY `ix_tmp_pd_daily_date` (`signal_date`);

  SET v_current_step = 'daily sequence';
  DROP TABLE IF EXISTS tmp_pd_daily_seq;
  CREATE TABLE tmp_pd_daily_seq AS
  SELECT
    ordered.*,
    @seq_num := IF(@seq_key = ordered.scrip, @seq_num + 1, 1) AS seq_num,
    @seq_key := ordered.scrip AS seq_key
  FROM (
    SELECT *
    FROM tmp_pd_daily
    ORDER BY scrip, signal_date
  ) ordered
  CROSS JOIN (SELECT @seq_key := '', @seq_num := 0) vars;

  ALTER TABLE tmp_pd_daily_seq
    ADD PRIMARY KEY (`scrip`, `seq_num`),
    ADD KEY `ix_tmp_pd_daily_seq_date` (`scrip`, `signal_date`);

  SET v_current_step = 'pivot candidates';
  DROP TABLE IF EXISTS tmp_pd_pivot_candidates;
  CREATE TABLE tmp_pd_pivot_candidates AS
  SELECT
    b.scrip,
    b.assetclass,
    'DAILY' AS frequency,
    b.signal_date AS pivot_date,
    CAST(CASE
      WHEN b.close_price >= p1.close_price
       AND b.close_price >= p2.close_price
       AND b.close_price >= p3.close_price
       AND b.close_price > n1.close_price
       AND b.close_price > n2.close_price
       AND b.close_price > n3.close_price THEN 'PEAK'
      WHEN b.close_price <= p1.close_price
       AND b.close_price <= p2.close_price
       AND b.close_price <= p3.close_price
       AND b.close_price < n1.close_price
       AND b.close_price < n2.close_price
       AND b.close_price < n3.close_price THEN 'TROUGH'
      ELSE NULL
    END AS CHAR(10)) AS pivot_type,
    b.close_price AS pivot_close,
    b.volume AS pivot_volume,
    b.seq_num,
    b.Combined_Signal AS daily_combined_signal,
    b.Combined_Signal_Ind AS daily_combined_signal_ind,
    b.LODeltaSignal AS daily_lo_delta_signal,
    b.SMADeltaTrend AS daily_sma_delta_trend,
    b.HARSIValue AS daily_harsi_value,
    b.HARSIZone AS daily_harsi_zone,
    b.HATrendCorrect AS daily_ha_trend_correct,
    b.HATrendSignal AS daily_ha_trend_signal,
    b.HAStrongSignal AS daily_ha_strong_signal,
    b.HAChangePct AS daily_ha_change_pct,
    b.HARallySeq AS daily_ha_rally_seq,
    b.HARallySlope AS daily_ha_rally_slope
  FROM tmp_pd_daily_seq b
  JOIN tmp_pd_daily_seq p1
    ON p1.scrip = b.scrip
   AND p1.seq_num = b.seq_num - 1
  JOIN tmp_pd_daily_seq p2
    ON p2.scrip = b.scrip
   AND p2.seq_num = b.seq_num - 2
  JOIN tmp_pd_daily_seq p3
    ON p3.scrip = b.scrip
   AND p3.seq_num = b.seq_num - 3
  JOIN tmp_pd_daily_seq n1
    ON n1.scrip = b.scrip
   AND n1.seq_num = b.seq_num + 1
  JOIN tmp_pd_daily_seq n2
    ON n2.scrip = b.scrip
   AND n2.seq_num = b.seq_num + 2
  JOIN tmp_pd_daily_seq n3
    ON n3.scrip = b.scrip
   AND n3.seq_num = b.seq_num + 3
  WHERE (b.close_price >= p1.close_price
     AND b.close_price >= p2.close_price
     AND b.close_price >= p3.close_price
     AND b.close_price > n1.close_price
     AND b.close_price > n2.close_price
     AND b.close_price > n3.close_price)
     OR (b.close_price <= p1.close_price
     AND b.close_price <= p2.close_price
     AND b.close_price <= p3.close_price
     AND b.close_price < n1.close_price
     AND b.close_price < n2.close_price
     AND b.close_price < n3.close_price);

  ALTER TABLE tmp_pd_pivot_candidates
    ADD KEY `ix_tmp_pd_pivot_candidates` (`scrip`, `seq_num`, `pivot_type`);

  SET v_current_step = 'pivot ranking';
  DROP TABLE IF EXISTS tmp_pd_pivot_ranked;
  CREATE TABLE tmp_pd_pivot_ranked AS
  SELECT
    pc.*,
    @pivot_rank := IF(@pivot_key = pc.scrip, @pivot_rank + 1, 1) AS pivot_rank,
    @pivot_key := pc.scrip AS pivot_key
  FROM (
    SELECT *
    FROM tmp_pd_pivot_candidates
    ORDER BY scrip, seq_num
  ) pc
  CROSS JOIN (SELECT @pivot_key := '', @pivot_rank := 0) vars;

  ALTER TABLE tmp_pd_pivot_ranked
    ADD PRIMARY KEY (`scrip`, `pivot_rank`),
    ADD KEY `ix_tmp_pd_pivot_ranked_date` (`scrip`, `pivot_date`, `pivot_type`);

  SET v_current_step = 'pivot filter';
  DROP TABLE IF EXISTS tmp_pd_pivots_filtered;
  CREATE TABLE tmp_pd_pivots_filtered AS
  SELECT
    c.*,
    p.pivot_date AS prev_pivot_date,
    p.pivot_type AS prev_pivot_type,
    p.pivot_close AS prev_pivot_close,
    p.seq_num AS prev_seq_num,
    ROUND((c.pivot_close - p.pivot_close) / NULLIF(p.pivot_close, 0) * 100, 2) AS move_from_prev_pct
  FROM tmp_pd_pivot_ranked c
  LEFT JOIN tmp_pd_pivot_ranked p
    ON p.scrip = c.scrip
   AND p.pivot_rank = c.pivot_rank - 1
  WHERE p.scrip IS NULL
     OR ABS((c.pivot_close - p.pivot_close) / NULLIF(p.pivot_close, 0) * 100) >= v_min_pivot_move_pct;

  ALTER TABLE tmp_pd_pivots_filtered
    ADD KEY `ix_tmp_pd_pivots_filtered` (`scrip`, `pivot_rank`);

  SET v_current_step = 'next pivot map';
  DROP TABLE IF EXISTS tmp_pd_next_pivot_rank;
  CREATE TABLE tmp_pd_next_pivot_rank AS
  SELECT
    c.scrip,
    c.pivot_rank,
    MIN(n.pivot_rank) AS next_pivot_rank
  FROM tmp_pd_pivots_filtered c
  LEFT JOIN tmp_pd_pivots_filtered n
    ON n.scrip = c.scrip
   AND n.pivot_rank > c.pivot_rank
  GROUP BY c.scrip, c.pivot_rank;

  ALTER TABLE tmp_pd_next_pivot_rank
    ADD PRIMARY KEY (`scrip`, `pivot_rank`);

  SET v_current_step = 'pivots final';
  DROP TABLE IF EXISTS tmp_pd_pivots_final;
  CREATE TABLE tmp_pd_pivots_final AS
  SELECT
    c.*,
    n.pivot_date AS next_pivot_date,
    n.pivot_type AS next_pivot_type,
    n.pivot_close AS next_pivot_close,
    n.seq_num AS next_seq_num,
    ROUND((n.pivot_close - c.pivot_close) / NULLIF(c.pivot_close, 0) * 100, 2) AS move_to_next_pct
  FROM tmp_pd_pivots_filtered c
  LEFT JOIN tmp_pd_next_pivot_rank nr
    ON nr.scrip = c.scrip
   AND nr.pivot_rank = c.pivot_rank
  LEFT JOIN tmp_pd_pivots_filtered n
    ON n.scrip = nr.scrip
   AND n.pivot_rank = nr.next_pivot_rank;

  ALTER TABLE tmp_pd_pivots_final
    ADD PRIMARY KEY (`scrip`, `pivot_date`, `pivot_type`),
    ADD KEY `ix_tmp_pd_pivots_final_rank` (`scrip`, `pivot_rank`);

  SET v_current_step = 'weekly history';
  DROP TABLE IF EXISTS tmp_pd_weekly;
  CREATE TABLE tmp_pd_weekly AS
  SELECT
    h.`SCRIP` AS scrip,
    h.`DATE` AS signal_date,
    h.`CLOSE` AS close_price,
    h.`HATrendCorrect`,
    h.`HATrendSignal`,
    h.`HAStrongSignal`,
    h.`HAChangePct`,
    h.`HARallySeq`,
    h.`HARallySlope`,
    e.`SMADeltaTrend`,
    e.`HARSIValue`,
    e.`HARSIZone`,
    e.`LODeltaSignal`,
    e.`Combined_Signal`,
    e.`Combined_Signal_Ind`
  FROM tmp_pd_universe u
  JOIN `jstockdata_hatrend` h
    ON h.`SCRIP` = u.scrip
   AND h.`Frequency` = 'WEEKLY\r'
  LEFT JOIN `jstockdata_hatrend_extend` e
    ON e.`SCRIP` = h.`SCRIP`
   AND e.`DATE` = h.`DATE`
   AND e.`FREQUENCY` = 'WEEKLY';

  ALTER TABLE tmp_pd_weekly
    ADD PRIMARY KEY (`scrip`, `signal_date`);

  SET v_current_step = 'pivot weekly map';
  DROP TABLE IF EXISTS tmp_pd_pivot_weekly_date;
  CREATE TABLE tmp_pd_pivot_weekly_date AS
  SELECT
    p.scrip,
    p.pivot_date,
    p.pivot_type,
    MAX(w.signal_date) AS weekly_signal_date
  FROM tmp_pd_pivots_final p
  LEFT JOIN tmp_pd_weekly w
    ON w.scrip = p.scrip
   AND w.signal_date <= p.pivot_date
  GROUP BY p.scrip, p.pivot_date, p.pivot_type;

  ALTER TABLE tmp_pd_pivot_weekly_date
    ADD PRIMARY KEY (`scrip`, `pivot_date`, `pivot_type`);

  SET v_current_step = 'insert major pivots';
  TRUNCATE TABLE `jstockdata_reco_major_pivots`;

  INSERT INTO `jstockdata_reco_major_pivots` (
    scrip, assetclass, frequency, pivot_date, pivot_type, pivot_close, pivot_volume, pivot_rank,
    prev_pivot_date, prev_pivot_type, prev_pivot_close, move_from_prev_pct, bars_from_prev_pivot,
    next_pivot_date, next_pivot_type, next_pivot_close, move_to_next_pct, bars_to_next_pivot,
    daily_combined_signal, daily_combined_signal_ind, daily_lo_delta_signal, daily_sma_delta_trend,
    daily_harsi_value, daily_harsi_zone, daily_ha_trend_correct, daily_ha_trend_signal,
    daily_ha_strong_signal, daily_ha_change_pct, daily_ha_rally_seq, daily_ha_rally_slope,
    weekly_signal_date, weekly_combined_signal, weekly_combined_signal_ind, weekly_lo_delta_signal,
    weekly_sma_delta_trend, weekly_harsi_value, weekly_harsi_zone, weekly_ha_trend_correct,
    weekly_ha_trend_signal, weekly_ha_strong_signal, weekly_ha_change_pct, weekly_ha_rally_seq,
    weekly_ha_rally_slope, generated_at
  )
  SELECT
    p.scrip,
    p.assetclass,
    p.frequency,
    p.pivot_date,
    p.pivot_type,
    p.pivot_close,
    p.pivot_volume,
    p.pivot_rank,
    p.prev_pivot_date,
    p.prev_pivot_type,
    p.prev_pivot_close,
    p.move_from_prev_pct,
    CASE WHEN p.prev_seq_num IS NULL THEN NULL ELSE p.seq_num - p.prev_seq_num END,
    p.next_pivot_date,
    p.next_pivot_type,
    p.next_pivot_close,
    p.move_to_next_pct,
    CASE WHEN p.next_seq_num IS NULL THEN NULL ELSE p.next_seq_num - p.seq_num END,
    p.daily_combined_signal,
    p.daily_combined_signal_ind,
    p.daily_lo_delta_signal,
    p.daily_sma_delta_trend,
    p.daily_harsi_value,
    p.daily_harsi_zone,
    p.daily_ha_trend_correct,
    p.daily_ha_trend_signal,
    p.daily_ha_strong_signal,
    p.daily_ha_change_pct,
    p.daily_ha_rally_seq,
    p.daily_ha_rally_slope,
    pwd.weekly_signal_date,
    w.Combined_Signal,
    w.Combined_Signal_Ind,
    w.LODeltaSignal,
    w.SMADeltaTrend,
    w.HARSIValue,
    w.HARSIZone,
    w.HATrendCorrect,
    w.HATrendSignal,
    w.HAStrongSignal,
    w.HAChangePct,
    w.HARallySeq,
    w.HARallySlope,
    v_generated_at
  FROM tmp_pd_pivots_final p
  LEFT JOIN tmp_pd_pivot_weekly_date pwd
    ON pwd.scrip = p.scrip
   AND pwd.pivot_date = p.pivot_date
   AND pwd.pivot_type = p.pivot_type
  LEFT JOIN tmp_pd_weekly w
    ON w.scrip = pwd.scrip
   AND w.signal_date = pwd.weekly_signal_date;

  SET v_current_step = 'latest daily';
  DROP TABLE IF EXISTS tmp_pd_latest_daily;
  CREATE TABLE tmp_pd_latest_daily AS
  SELECT d.*
  FROM tmp_pd_daily d
  JOIN (
    SELECT scrip, MAX(signal_date) AS signal_date
    FROM tmp_pd_daily
    GROUP BY scrip
  ) mx ON mx.scrip = d.scrip AND mx.signal_date = d.signal_date;
  ALTER TABLE tmp_pd_latest_daily ADD PRIMARY KEY (`scrip`);

  SET v_current_step = 'latest weekly';
  DROP TABLE IF EXISTS tmp_pd_latest_weekly;
  CREATE TABLE tmp_pd_latest_weekly AS
  SELECT w.*
  FROM tmp_pd_weekly w
  JOIN (
    SELECT scrip, MAX(signal_date) AS signal_date
    FROM tmp_pd_weekly
    GROUP BY scrip
  ) mx ON mx.scrip = w.scrip AND mx.signal_date = w.signal_date;
  ALTER TABLE tmp_pd_latest_weekly ADD PRIMARY KEY (`scrip`);

  SET v_current_step = 'last pivot';
  DROP TABLE IF EXISTS tmp_pd_last_pivot_rank;
  CREATE TABLE tmp_pd_last_pivot_rank AS
  SELECT scrip, MAX(pivot_rank) AS pivot_rank
  FROM `jstockdata_reco_major_pivots`
  WHERE frequency = 'DAILY'
  GROUP BY scrip;
  ALTER TABLE tmp_pd_last_pivot_rank ADD PRIMARY KEY (`scrip`);

  DROP TABLE IF EXISTS tmp_pd_last_pivot;
  CREATE TABLE tmp_pd_last_pivot AS
  SELECT p.*
  FROM `jstockdata_reco_major_pivots` p
  JOIN tmp_pd_last_pivot_rank mx
    ON mx.scrip = p.scrip
   AND mx.pivot_rank = p.pivot_rank
  WHERE p.frequency = 'DAILY';
  ALTER TABLE tmp_pd_last_pivot ADD PRIMARY KEY (`scrip`);

  SET v_current_step = 'projection context';
  DROP TABLE IF EXISTS tmp_pd_latest_context;
  CREATE TABLE tmp_pd_latest_context AS
  SELECT
    d.scrip,
    CONCAT(
      'CS=', COALESCE(d.Combined_Signal, ''),
      '|CSI=', COALESCE(d.Combined_Signal_Ind, ''),
      '|SMA=', COALESCE(d.SMADeltaTrend, ''),
      '|LO=', COALESCE(d.LODeltaSignal, '')
    ) AS signal_context_key
  FROM tmp_pd_latest_daily d;
  ALTER TABLE tmp_pd_latest_context ADD PRIMARY KEY (`scrip`);

  SET v_current_step = 'projection best';
  DROP TABLE IF EXISTS tmp_pd_projection_pick;
  CREATE TABLE tmp_pd_projection_pick AS
  SELECT
    p.scrip,
    MIN(p.horizon_bars) AS horizon_bars
  FROM `jstockdata_reco_projection` p
  JOIN tmp_pd_latest_context c
    ON c.scrip = p.scrip
   AND c.signal_context_key = p.signal_context_key
  WHERE p.frequency = 'DAILY'
    AND p.horizon_bars IN (5, 10)
  GROUP BY p.scrip;
  ALTER TABLE tmp_pd_projection_pick ADD PRIMARY KEY (`scrip`);

  DROP TABLE IF EXISTS tmp_pd_projection_best;
  CREATE TABLE tmp_pd_projection_best AS
  SELECT p.*
  FROM `jstockdata_reco_projection` p
  JOIN tmp_pd_projection_pick pick
    ON pick.scrip = p.scrip
   AND pick.horizon_bars = p.horizon_bars
  JOIN tmp_pd_latest_context c
    ON c.scrip = p.scrip
   AND c.signal_context_key = p.signal_context_key
  WHERE p.frequency = 'DAILY';
  ALTER TABLE tmp_pd_projection_best ADD PRIMARY KEY (`scrip`);

  SET v_current_step = 'scoring';
  DROP TABLE IF EXISTS tmp_pd_scored;
  CREATE TABLE tmp_pd_scored AS
  SELECT
    s.scrip,
    s.assetclass,
    s.company_name,
    s.source_rank,
    s.reco_universe_status,
    s.reco_universe_rank,
    d.signal_date AS latest_daily_date,
    d.close_price AS latest_daily_close,
    w.signal_date AS latest_weekly_date,
    w.close_price AS latest_weekly_close,
    d.Combined_Signal AS daily_combined_signal,
    w.Combined_Signal AS weekly_combined_signal,
    d.Combined_Signal_Ind AS daily_combined_signal_ind,
    w.Combined_Signal_Ind AS weekly_combined_signal_ind,
    d.LODeltaSignal AS daily_lo_delta_signal,
    w.LODeltaSignal AS weekly_lo_delta_signal,
    d.SMADeltaTrend AS daily_sma_delta_trend,
    w.SMADeltaTrend AS weekly_sma_delta_trend,
    dm.momentum_direction AS daily_momentum_direction,
    dm.momentum_phase AS daily_momentum_phase,
    dm.momentum_confidence_pct AS daily_momentum_confidence_pct,
    dm.momentum_score AS daily_momentum_score,
    dm.predicted_5bar_return_pct AS daily_predicted_5bar_return_pct,
    dm.predicted_10bar_return_pct AS daily_predicted_10bar_return_pct,
    dm.momentum_reversal_risk_pct AS daily_reversal_risk_pct,
    wm.momentum_direction AS weekly_momentum_direction,
    wm.momentum_phase AS weekly_momentum_phase,
    wm.momentum_confidence_pct AS weekly_momentum_confidence_pct,
    wm.momentum_score AS weekly_momentum_score,
    wm.predicted_5bar_return_pct AS weekly_predicted_5bar_return_pct,
    wm.predicted_10bar_return_pct AS weekly_predicted_10bar_return_pct,
    wm.momentum_reversal_risk_pct AS weekly_reversal_risk_pct,
    p.frequency AS projection_frequency,
    p.signal_context_key AS projection_context_key,
    p.horizon_bars AS projection_horizon_bars,
    p.sample_size AS projection_sample_size,
    p.upward_probability_pct AS projection_upward_probability_pct,
    p.downward_probability_pct AS projection_downward_probability_pct,
    p.expected_return_pct AS projection_expected_return_pct,
    p.confidence_score AS projection_confidence_score,
    lp.pivot_type AS last_pivot_type,
    lp.pivot_date AS last_pivot_date,
    lp.pivot_close AS last_pivot_close,
    ROUND((d.close_price - lp.pivot_close) / NULLIF(lp.pivot_close, 0) * 100, 2) AS move_from_last_pivot_pct,
    ns.swing_news_signal AS news_signal,
    ns.catalyst_score AS news_catalyst_score,
    ns.news_risk_score AS news_risk_score,
    ns.top_headline AS top_news_headline,
    (
      CASE WHEN d.Combined_Signal = 'BUY' THEN 16 WHEN d.Combined_Signal = 'SELL' THEN -16 ELSE 0 END
      + CASE WHEN w.Combined_Signal = 'BUY' THEN 24 WHEN w.Combined_Signal = 'SELL' THEN -24 ELSE 0 END
      + CASE WHEN d.LODeltaSignal = 'BUY' THEN 8 WHEN d.LODeltaSignal = 'SELL' THEN -8 ELSE 0 END
      + CASE WHEN w.LODeltaSignal = 'BUY' THEN 12 WHEN w.LODeltaSignal = 'SELL' THEN -12 ELSE 0 END
      + CASE WHEN dm.momentum_direction = 'BULLISH' THEN 14 WHEN dm.momentum_direction = 'BEARISH' THEN -14 ELSE 0 END
      + CASE WHEN wm.momentum_direction = 'BULLISH' THEN 20 WHEN wm.momentum_direction = 'BEARISH' THEN -20 ELSE 0 END
      + CASE WHEN dm.momentum_phase IN ('EARLY','BULLISH_ACCELERATING') THEN 8 WHEN dm.momentum_phase IN ('BEARISH_ACCELERATING') THEN -8 WHEN dm.momentum_phase IN ('MATURE','REVERSAL_RISK','WEAKENING') THEN -4 ELSE 0 END
      + CASE WHEN wm.momentum_phase IN ('EARLY','BULLISH_ACCELERATING') THEN 12 WHEN wm.momentum_phase IN ('BEARISH_ACCELERATING') THEN -12 WHEN wm.momentum_phase IN ('MATURE','REVERSAL_RISK','WEAKENING') THEN -6 ELSE 0 END
      + LEAST(8, GREATEST(-8, COALESCE(dm.predicted_10bar_return_pct, 0) * 2))
      + LEAST(10, GREATEST(-10, COALESCE(wm.predicted_10bar_return_pct, 0) * 2))
      + LEAST(8, GREATEST(-8, COALESCE(p.expected_return_pct, 0) * 3))
      + LEAST(6, GREATEST(-6, COALESCE(ns.catalyst_score, 0) / 10))
      - LEAST(8, COALESCE(ns.news_risk_score, 0) / 10)
    ) AS direction_score,
    (
      CASE WHEN w.Combined_Signal = 'BUY' THEN 30 WHEN w.Combined_Signal = 'SELL' THEN -30 ELSE 0 END
      + CASE WHEN w.LODeltaSignal = 'BUY' THEN 15 WHEN w.LODeltaSignal = 'SELL' THEN -15 ELSE 0 END
      + CASE WHEN w.SMADeltaTrend = 'UP' THEN 10 WHEN w.SMADeltaTrend = 'DOWN' THEN -10 ELSE 0 END
      + CASE WHEN wm.momentum_direction = 'BULLISH' THEN 25 WHEN wm.momentum_direction = 'BEARISH' THEN -25 ELSE 0 END
      + CASE WHEN wm.momentum_phase IN ('EARLY','BULLISH_ACCELERATING') THEN 15 WHEN wm.momentum_phase = 'BEARISH_ACCELERATING' THEN -15 WHEN wm.momentum_phase IN ('MATURE','REVERSAL_RISK','WEAKENING') THEN -8 ELSE 0 END
      + LEAST(10, GREATEST(-10, COALESCE(wm.predicted_10bar_return_pct, 0) * 2))
    ) AS weekly_score
  FROM tmp_pd_universe s
  LEFT JOIN tmp_pd_latest_daily d ON d.scrip = s.scrip
  LEFT JOIN tmp_pd_latest_weekly w ON w.scrip = s.scrip
  LEFT JOIN `jstockdata_reco_momentum_signal` dm
    ON dm.scrip = s.scrip AND dm.frequency = 'DAILY'
  LEFT JOIN `jstockdata_reco_momentum_signal` wm
    ON wm.scrip = s.scrip AND wm.frequency = 'WEEKLY'
  LEFT JOIN tmp_pd_projection_best p ON p.scrip = s.scrip
  LEFT JOIN tmp_pd_last_pivot lp ON lp.scrip = s.scrip
  LEFT JOIN `jstockdata_reco_news_signal` ns ON ns.scrip = s.scrip;

  ALTER TABLE tmp_pd_scored ADD PRIMARY KEY (`scrip`);

  SET v_current_step = 'insert predictive direction';
  TRUNCATE TABLE `jstockdata_reco_predictive_direction`;

  INSERT INTO `jstockdata_reco_predictive_direction` (
    scrip, assetclass, company_name, source_rank, reco_universe_status, reco_universe_rank, generated_at,
    latest_daily_date, latest_daily_close, latest_weekly_date, latest_weekly_close,
    daily_combined_signal, weekly_combined_signal, daily_combined_signal_ind, weekly_combined_signal_ind,
    daily_lo_delta_signal, weekly_lo_delta_signal, daily_sma_delta_trend, weekly_sma_delta_trend,
    daily_momentum_direction, daily_momentum_phase, daily_momentum_confidence_pct, daily_momentum_score,
    daily_predicted_5bar_return_pct, daily_predicted_10bar_return_pct, daily_reversal_risk_pct,
    weekly_momentum_direction, weekly_momentum_phase, weekly_momentum_confidence_pct, weekly_momentum_score,
    weekly_predicted_5bar_return_pct, weekly_predicted_10bar_return_pct, weekly_reversal_risk_pct,
    expected_direction, direction_probability_pct, direction_confidence_pct,
    weekly_verdict, weekly_prediction_probability_pct, weekly_verdict_reason,
    projection_frequency, projection_context_key, projection_horizon_bars, projection_sample_size,
    projection_upward_probability_pct, projection_downward_probability_pct,
    projection_expected_return_pct, projection_confidence_score,
    last_pivot_type, last_pivot_date, last_pivot_close, move_from_last_pivot_pct,
    news_signal, news_catalyst_score, news_risk_score, top_news_headline, direction_reason
  )
  SELECT
    scrip,
    assetclass,
    company_name,
    source_rank,
    reco_universe_status,
    reco_universe_rank,
    v_generated_at,
    latest_daily_date,
    latest_daily_close,
    latest_weekly_date,
    latest_weekly_close,
    daily_combined_signal,
    weekly_combined_signal,
    daily_combined_signal_ind,
    weekly_combined_signal_ind,
    daily_lo_delta_signal,
    weekly_lo_delta_signal,
    daily_sma_delta_trend,
    weekly_sma_delta_trend,
    daily_momentum_direction,
    daily_momentum_phase,
    daily_momentum_confidence_pct,
    daily_momentum_score,
    daily_predicted_5bar_return_pct,
    daily_predicted_10bar_return_pct,
    daily_reversal_risk_pct,
    weekly_momentum_direction,
    weekly_momentum_phase,
    weekly_momentum_confidence_pct,
    weekly_momentum_score,
    weekly_predicted_5bar_return_pct,
    weekly_predicted_10bar_return_pct,
    weekly_reversal_risk_pct,
    CASE
      WHEN direction_score >= 35 THEN 'BULLISH'
      WHEN direction_score <= -35 THEN 'BEARISH'
      WHEN direction_score BETWEEN -15 AND 15 THEN 'NEUTRAL'
      ELSE 'MIXED'
    END AS expected_direction,
    ROUND(LEAST(95, GREATEST(5, 50 + direction_score / 2)), 2) AS direction_probability_pct,
    ROUND(LEAST(100, GREATEST(0,
      ABS(direction_score) * 0.55
      + COALESCE(daily_momentum_confidence_pct, 0) * 0.18
      + COALESCE(weekly_momentum_confidence_pct, 0) * 0.22
      + CASE WHEN daily_combined_signal = weekly_combined_signal AND daily_combined_signal IN ('BUY','SELL') THEN 12 ELSE 0 END
      + CASE WHEN projection_confidence_score IS NOT NULL THEN LEAST(10, projection_confidence_score / 10) ELSE 0 END
      - COALESCE(daily_reversal_risk_pct, 0) * 0.08
      - COALESCE(weekly_reversal_risk_pct, 0) * 0.10
    )), 2) AS direction_confidence_pct,
    CASE
      WHEN weekly_score >= 55 THEN 'STRONG_BULLISH'
      WHEN weekly_score >= 25 THEN 'BULLISH'
      WHEN weekly_score <= -55 THEN 'STRONG_BEARISH'
      WHEN weekly_score <= -25 THEN 'BEARISH'
      WHEN weekly_score BETWEEN -12 AND 12 THEN 'NEUTRAL'
      ELSE 'CAUTION'
    END AS weekly_verdict,
    ROUND(LEAST(95, GREATEST(5, 50 + weekly_score / 2)), 2) AS weekly_prediction_probability_pct,
    CONCAT(
      'Weekly CS=', COALESCE(weekly_combined_signal, 'NA'),
      ', weekly momentum=', COALESCE(weekly_momentum_direction, 'NA'),
      '/', COALESCE(weekly_momentum_phase, 'NA'),
      ', weekly confidence=', COALESCE(CAST(weekly_momentum_confidence_pct AS CHAR), 'NA'),
      ', weekly score=', ROUND(weekly_score, 2)
    ) AS weekly_verdict_reason,
    projection_frequency,
    projection_context_key,
    projection_horizon_bars,
    projection_sample_size,
    projection_upward_probability_pct,
    projection_downward_probability_pct,
    projection_expected_return_pct,
    projection_confidence_score,
    last_pivot_type,
    last_pivot_date,
    last_pivot_close,
    move_from_last_pivot_pct,
    news_signal,
    news_catalyst_score,
    news_risk_score,
    top_news_headline,
    CONCAT(
      'Daily CS=', COALESCE(daily_combined_signal, 'NA'),
      ', weekly CS=', COALESCE(weekly_combined_signal, 'NA'),
      ', daily momentum=', COALESCE(daily_momentum_direction, 'NA'),
      '/', COALESCE(daily_momentum_phase, 'NA'),
      ', weekly momentum=', COALESCE(weekly_momentum_direction, 'NA'),
      '/', COALESCE(weekly_momentum_phase, 'NA'),
      ', projection ER=', COALESCE(CAST(projection_expected_return_pct AS CHAR), 'NA'),
      ', news=', COALESCE(news_signal, 'NA'),
      ', score=', ROUND(direction_score, 2)
    ) AS direction_reason
  FROM tmp_pd_scored;

  SET v_current_step = 'cleanup';
  DROP TABLE IF EXISTS tmp_pd_scored;
  DROP TABLE IF EXISTS tmp_pd_projection_best;
  DROP TABLE IF EXISTS tmp_pd_projection_pick;
  DROP TABLE IF EXISTS tmp_pd_latest_context;
  DROP TABLE IF EXISTS tmp_pd_last_pivot;
  DROP TABLE IF EXISTS tmp_pd_last_pivot_rank;
  DROP TABLE IF EXISTS tmp_pd_latest_weekly;
  DROP TABLE IF EXISTS tmp_pd_latest_daily;
  DROP TABLE IF EXISTS tmp_pd_pivot_weekly_date;
  DROP TABLE IF EXISTS tmp_pd_weekly;
  DROP TABLE IF EXISTS tmp_pd_pivots_final;
  DROP TABLE IF EXISTS tmp_pd_next_pivot_rank;
  DROP TABLE IF EXISTS tmp_pd_pivots_filtered;
  DROP TABLE IF EXISTS tmp_pd_pivot_ranked;
  DROP TABLE IF EXISTS tmp_pd_pivot_candidates;
  DROP TABLE IF EXISTS tmp_pd_daily_seq;
  DROP TABLE IF EXISTS tmp_pd_daily;
  DROP TABLE IF EXISTS tmp_pd_universe;

  CALL reco_runlog_mark(
    'reco_predictive_direction_refresh',
    'SUCCESS',
    CONCAT('Optimized refresh completed; generated_at=', v_generated_at)
  );
END$$
DELIMITER ;
