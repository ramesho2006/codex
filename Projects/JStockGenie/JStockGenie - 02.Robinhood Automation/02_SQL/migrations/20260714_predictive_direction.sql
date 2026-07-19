-- Predictive direction analysis.
--
-- jstockdata_reco_major_pivots keeps historical local peak/trough context.
-- jstockdata_reco_predictive_direction keeps the latest screener-friendly
-- direction, probability, confidence, and weekly verdict per scrip.

CREATE TABLE IF NOT EXISTS `jstockdata_reco_major_pivots` (
  `scrip` VARCHAR(20) NOT NULL,
  `assetclass` VARCHAR(30) NULL,
  `frequency` VARCHAR(20) NOT NULL,
  `pivot_date` INT NOT NULL,
  `pivot_type` VARCHAR(10) NOT NULL,
  `pivot_close` DECIMAL(12,2) NOT NULL,
  `pivot_volume` BIGINT UNSIGNED NULL,
  `pivot_rank` INT NOT NULL,
  `prev_pivot_date` INT NULL,
  `prev_pivot_type` VARCHAR(10) NULL,
  `prev_pivot_close` DECIMAL(12,2) NULL,
  `move_from_prev_pct` DECIMAL(10,2) NULL,
  `bars_from_prev_pivot` INT NULL,
  `next_pivot_date` INT NULL,
  `next_pivot_type` VARCHAR(10) NULL,
  `next_pivot_close` DECIMAL(12,2) NULL,
  `move_to_next_pct` DECIMAL(10,2) NULL,
  `bars_to_next_pivot` INT NULL,
  `daily_combined_signal` VARCHAR(10) NULL,
  `daily_combined_signal_ind` VARCHAR(10) NULL,
  `daily_lo_delta_signal` VARCHAR(10) NULL,
  `daily_sma_delta_trend` VARCHAR(10) NULL,
  `daily_harsi_value` DECIMAL(12,2) NULL,
  `daily_harsi_zone` VARCHAR(10) NULL,
  `daily_ha_trend_correct` VARCHAR(10) NULL,
  `daily_ha_trend_signal` VARCHAR(10) NULL,
  `daily_ha_strong_signal` VARCHAR(15) NULL,
  `daily_ha_change_pct` DECIMAL(12,2) NULL,
  `daily_ha_rally_seq` INT NULL,
  `daily_ha_rally_slope` DECIMAL(12,2) NULL,
  `weekly_signal_date` INT NULL,
  `weekly_combined_signal` VARCHAR(10) NULL,
  `weekly_combined_signal_ind` VARCHAR(10) NULL,
  `weekly_lo_delta_signal` VARCHAR(10) NULL,
  `weekly_sma_delta_trend` VARCHAR(10) NULL,
  `weekly_harsi_value` DECIMAL(12,2) NULL,
  `weekly_harsi_zone` VARCHAR(10) NULL,
  `weekly_ha_trend_correct` VARCHAR(10) NULL,
  `weekly_ha_trend_signal` VARCHAR(10) NULL,
  `weekly_ha_strong_signal` VARCHAR(15) NULL,
  `weekly_ha_change_pct` DECIMAL(12,2) NULL,
  `weekly_ha_rally_seq` INT NULL,
  `weekly_ha_rally_slope` DECIMAL(12,2) NULL,
  `generated_at` DATETIME NOT NULL,
  PRIMARY KEY (`scrip`, `frequency`, `pivot_date`, `pivot_type`),
  KEY `ix_reco_major_pivots_date` (`pivot_date`, `pivot_type`),
  KEY `ix_reco_major_pivots_scrip_rank` (`scrip`, `frequency`, `pivot_rank`),
  KEY `ix_reco_major_pivots_move` (`pivot_type`, `move_from_prev_pct`, `move_to_next_pct`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `jstockdata_reco_predictive_direction` (
  `scrip` VARCHAR(20) NOT NULL,
  `assetclass` VARCHAR(30) NULL,
  `company_name` VARCHAR(120) NULL,
  `source_rank` INT NULL,
  `reco_universe_status` VARCHAR(10) NULL,
  `reco_universe_rank` INT NULL,
  `generated_at` DATETIME NOT NULL,
  `latest_daily_date` INT NULL,
  `latest_daily_close` DECIMAL(12,2) NULL,
  `latest_weekly_date` INT NULL,
  `latest_weekly_close` DECIMAL(12,2) NULL,
  `daily_combined_signal` VARCHAR(10) NULL,
  `weekly_combined_signal` VARCHAR(10) NULL,
  `daily_combined_signal_ind` VARCHAR(10) NULL,
  `weekly_combined_signal_ind` VARCHAR(10) NULL,
  `daily_lo_delta_signal` VARCHAR(10) NULL,
  `weekly_lo_delta_signal` VARCHAR(10) NULL,
  `daily_sma_delta_trend` VARCHAR(10) NULL,
  `weekly_sma_delta_trend` VARCHAR(10) NULL,
  `daily_momentum_direction` VARCHAR(12) NULL,
  `daily_momentum_phase` VARCHAR(20) NULL,
  `daily_momentum_confidence_pct` DECIMAL(6,2) NULL,
  `daily_momentum_score` DECIMAL(8,2) NULL,
  `daily_predicted_5bar_return_pct` DECIMAL(10,2) NULL,
  `daily_predicted_10bar_return_pct` DECIMAL(10,2) NULL,
  `daily_reversal_risk_pct` DECIMAL(6,2) NULL,
  `weekly_momentum_direction` VARCHAR(12) NULL,
  `weekly_momentum_phase` VARCHAR(20) NULL,
  `weekly_momentum_confidence_pct` DECIMAL(6,2) NULL,
  `weekly_momentum_score` DECIMAL(8,2) NULL,
  `weekly_predicted_5bar_return_pct` DECIMAL(10,2) NULL,
  `weekly_predicted_10bar_return_pct` DECIMAL(10,2) NULL,
  `weekly_reversal_risk_pct` DECIMAL(6,2) NULL,
  `expected_direction` VARCHAR(20) NOT NULL,
  `direction_probability_pct` DECIMAL(6,2) NOT NULL,
  `direction_confidence_pct` DECIMAL(6,2) NOT NULL,
  `weekly_verdict` VARCHAR(20) NOT NULL,
  `weekly_prediction_probability_pct` DECIMAL(6,2) NOT NULL,
  `weekly_verdict_reason` VARCHAR(500) NULL,
  `projection_frequency` VARCHAR(20) NULL,
  `projection_context_key` VARCHAR(160) NULL,
  `projection_horizon_bars` INT NULL,
  `projection_sample_size` INT NULL,
  `projection_upward_probability_pct` DECIMAL(6,2) NULL,
  `projection_downward_probability_pct` DECIMAL(6,2) NULL,
  `projection_expected_return_pct` DECIMAL(10,2) NULL,
  `projection_confidence_score` DECIMAL(6,2) NULL,
  `last_pivot_type` VARCHAR(10) NULL,
  `last_pivot_date` INT NULL,
  `last_pivot_close` DECIMAL(12,2) NULL,
  `move_from_last_pivot_pct` DECIMAL(10,2) NULL,
  `news_signal` VARCHAR(20) NULL,
  `news_catalyst_score` DECIMAL(10,2) NULL,
  `news_risk_score` DECIMAL(10,2) NULL,
  `top_news_headline` VARCHAR(500) NULL,
  `direction_reason` VARCHAR(700) NULL,
  PRIMARY KEY (`scrip`),
  KEY `ix_reco_predictive_direction_main` (`expected_direction`, `direction_confidence_pct`, `direction_probability_pct`),
  KEY `ix_reco_predictive_direction_weekly` (`weekly_verdict`, `weekly_prediction_probability_pct`),
  KEY `ix_reco_predictive_direction_signals` (`daily_combined_signal`, `weekly_combined_signal`),
  KEY `ix_reco_predictive_direction_universe` (`reco_universe_status`, `reco_universe_rank`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP PROCEDURE IF EXISTS `reco_predictive_direction_refresh`;

DELIMITER $$
CREATE PROCEDURE `reco_predictive_direction_refresh`()
BEGIN
  DECLARE v_generated_at DATETIME DEFAULT NOW();
  DECLARE v_min_pivot_move_pct DECIMAL(10,2) DEFAULT 7.00;
  DECLARE v_pivot_window INT DEFAULT 10;

  DROP TABLE IF EXISTS tmp_pd_daily;
  CREATE TABLE tmp_pd_daily AS
  SELECT
    h.`SCRIP` AS scrip,
    'UNKNOWN' AS assetclass,
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
  FROM `jstockdata_hatrend` h
  LEFT JOIN `jstockdata_hatrend_extend` e
    ON e.`SCRIP` = h.`SCRIP`
   AND e.`DATE` = h.`DATE`
   AND e.`FREQUENCY` = 'DAILY'
  WHERE h.`Frequency` = 'DAILY\r';

  ALTER TABLE tmp_pd_daily
    ADD PRIMARY KEY (`scrip`, `signal_date`),
    ADD KEY `ix_tmp_pd_daily_asset` (`assetclass`, `signal_date`);

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

  DROP TABLE IF EXISTS tmp_pd_pivot_candidates;
  CREATE TABLE tmp_pd_pivot_candidates AS
  SELECT
    b.scrip,
    b.assetclass,
    'DAILY' AS frequency,
    b.signal_date AS pivot_date,
    CAST(CASE
      WHEN b.close_price = MAX(w.close_price) THEN 'PEAK'
      WHEN b.close_price = MIN(w.close_price) THEN 'TROUGH'
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
  JOIN tmp_pd_daily_seq w
    ON w.scrip = b.scrip
   AND w.seq_num BETWEEN b.seq_num - v_pivot_window AND b.seq_num + v_pivot_window
  GROUP BY
    b.scrip, b.assetclass, b.signal_date, b.close_price, b.volume, b.seq_num,
    b.Combined_Signal, b.Combined_Signal_Ind, b.LODeltaSignal, b.SMADeltaTrend,
    b.HARSIValue, b.HARSIZone, b.HATrendCorrect, b.HATrendSignal, b.HAStrongSignal,
    b.HAChangePct, b.HARallySeq, b.HARallySlope
  HAVING
    b.close_price = MAX(w.close_price)
    OR b.close_price = MIN(w.close_price);

  ALTER TABLE tmp_pd_pivot_candidates
    ADD KEY `ix_tmp_pd_pivot_candidates` (`scrip`, `seq_num`, `pivot_type`);

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
  LEFT JOIN tmp_pd_pivots_filtered n
    ON n.scrip = c.scrip
   AND n.pivot_rank = (
      SELECT MIN(n2.pivot_rank)
      FROM tmp_pd_pivots_filtered n2
      WHERE n2.scrip = c.scrip
        AND n2.pivot_rank > c.pivot_rank
   );

  ALTER TABLE tmp_pd_pivots_final
    ADD PRIMARY KEY (`scrip`, `pivot_date`, `pivot_type`),
    ADD KEY `ix_tmp_pd_pivots_final_rank` (`scrip`, `pivot_rank`);

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
  FROM `jstockdata_hatrend` h
  LEFT JOIN `jstockdata_hatrend_extend` e
    ON e.`SCRIP` = h.`SCRIP`
   AND e.`DATE` = h.`DATE`
   AND e.`FREQUENCY` = 'WEEKLY'
  WHERE h.`Frequency` = 'WEEKLY\r';

  ALTER TABLE tmp_pd_weekly
    ADD PRIMARY KEY (`scrip`, `signal_date`);

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
    COALESCE(sp.`AssetClass`, p.assetclass),
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
    w.signal_date,
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
  LEFT JOIN `jstockdata_scrips` sp
    ON sp.`Scrip` = p.scrip
  LEFT JOIN tmp_pd_weekly w
    ON w.scrip = p.scrip
   AND w.signal_date = (
      SELECT MAX(w2.signal_date)
      FROM tmp_pd_weekly w2
      WHERE w2.scrip = p.scrip
        AND w2.signal_date <= p.pivot_date
   );

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

  DROP TABLE IF EXISTS tmp_pd_last_pivot;
  CREATE TABLE tmp_pd_last_pivot AS
  SELECT p.*
  FROM `jstockdata_reco_major_pivots` p
  JOIN (
    SELECT scrip, MAX(pivot_date) AS pivot_date
    FROM `jstockdata_reco_major_pivots`
    WHERE frequency = 'DAILY'
    GROUP BY scrip
  ) mx ON mx.scrip = p.scrip AND mx.pivot_date = p.pivot_date
  WHERE p.frequency = 'DAILY';
  ALTER TABLE tmp_pd_last_pivot ADD PRIMARY KEY (`scrip`);

  DROP TABLE IF EXISTS tmp_pd_projection_best;
  CREATE TABLE tmp_pd_projection_best AS
  SELECT p.*
  FROM `jstockdata_reco_projection` p
  JOIN (
    SELECT
      p2.scrip,
      MIN(p2.horizon_bars) AS horizon_bars
    FROM `jstockdata_reco_projection` p2
    JOIN tmp_pd_latest_daily d ON d.scrip = p2.scrip
    WHERE p2.frequency = 'DAILY'
      AND p2.signal_context_key = CONCAT(
        'CS=', COALESCE(d.Combined_Signal, ''),
        '|CSI=', COALESCE(d.Combined_Signal_Ind, ''),
        '|SMA=', COALESCE(d.SMADeltaTrend, ''),
        '|LO=', COALESCE(d.LODeltaSignal, '')
      )
      AND p2.horizon_bars IN (5, 10)
    GROUP BY p2.scrip
  ) pick ON pick.scrip = p.scrip AND pick.horizon_bars = p.horizon_bars
  JOIN tmp_pd_latest_daily d ON d.scrip = p.scrip
  WHERE p.frequency = 'DAILY'
    AND p.signal_context_key = CONCAT(
      'CS=', COALESCE(d.Combined_Signal, ''),
      '|CSI=', COALESCE(d.Combined_Signal_Ind, ''),
      '|SMA=', COALESCE(d.SMADeltaTrend, ''),
      '|LO=', COALESCE(d.LODeltaSignal, '')
    );
  ALTER TABLE tmp_pd_projection_best ADD PRIMARY KEY (`scrip`);

  DROP TABLE IF EXISTS tmp_pd_scored;
  CREATE TABLE tmp_pd_scored AS
  SELECT
    s.`Scrip` AS scrip,
    s.`AssetClass` AS assetclass,
    s.`Company Name` AS company_name,
    s.`Rank` AS source_rank,
    s.`RecoUniverseStatus` AS reco_universe_status,
    s.`RecoUniverseRank` AS reco_universe_rank,
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
  FROM `jstockdata_scrips` s
  LEFT JOIN tmp_pd_latest_daily d ON d.scrip = s.`Scrip`
  LEFT JOIN tmp_pd_latest_weekly w ON w.scrip = s.`Scrip`
  LEFT JOIN `jstockdata_reco_momentum_signal` dm
    ON dm.scrip = s.`Scrip` AND dm.frequency = 'DAILY'
  LEFT JOIN `jstockdata_reco_momentum_signal` wm
    ON wm.scrip = s.`Scrip` AND wm.frequency = 'WEEKLY'
  LEFT JOIN tmp_pd_projection_best p ON p.scrip = s.`Scrip`
  LEFT JOIN tmp_pd_last_pivot lp ON lp.scrip = s.`Scrip`
  LEFT JOIN `jstockdata_reco_news_signal` ns ON ns.scrip = s.`Scrip`
  WHERE s.`Scrip` IS NOT NULL;

  ALTER TABLE tmp_pd_scored ADD PRIMARY KEY (`scrip`);

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

  DROP TABLE IF EXISTS tmp_pd_scored;
  DROP TABLE IF EXISTS tmp_pd_projection_best;
  DROP TABLE IF EXISTS tmp_pd_last_pivot;
  DROP TABLE IF EXISTS tmp_pd_latest_weekly;
  DROP TABLE IF EXISTS tmp_pd_latest_daily;
  DROP TABLE IF EXISTS tmp_pd_weekly;
  DROP TABLE IF EXISTS tmp_pd_pivots_final;
  DROP TABLE IF EXISTS tmp_pd_pivots_filtered;
  DROP TABLE IF EXISTS tmp_pd_pivot_ranked;
  DROP TABLE IF EXISTS tmp_pd_pivot_candidates;
  DROP TABLE IF EXISTS tmp_pd_daily_seq;
  DROP TABLE IF EXISTS tmp_pd_daily;
END$$
DELIMITER ;
