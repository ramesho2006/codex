CREATE TABLE IF NOT EXISTS `jstockdata_momentum_signal` (
  `symbol` VARCHAR(20) NOT NULL,
  `frequency` VARCHAR(20) NOT NULL,
  `signal_date` INT NOT NULL,
  `close_price` DECIMAL(12,2) NULL,
  `momentum_score` DECIMAL(8,2) NULL,
  `momentum_direction` VARCHAR(12) NOT NULL,
  `momentum_phase` VARCHAR(20) NOT NULL,
  `momentum_confidence_pct` DECIMAL(6,2) NULL,
  `momentum_age_bars` INT NULL,
  `momentum_acceleration` DECIMAL(10,2) NULL,
  `momentum_exhaustion_score` DECIMAL(8,2) NULL,
  `momentum_reversal_risk_pct` DECIMAL(6,2) NULL,
  `close_change_3bar_pct` DECIMAL(10,2) NULL,
  `close_change_5bar_pct` DECIMAL(10,2) NULL,
  `ha_change_pct` DECIMAL(10,2) NULL,
  `ha_change_3bar_delta` DECIMAL(10,2) NULL,
  `ha_trend_correct` VARCHAR(10) NULL,
  `ha_trend_signal` VARCHAR(10) NULL,
  `ha_strong_signal` VARCHAR(15) NULL,
  `ha_rally_seq` INT NULL,
  `ha_rally_slope` DECIMAL(12,2) NULL,
  `ha_rally_angle` DECIMAL(12,2) NULL,
  `harsi_value` DECIMAL(12,2) NULL,
  `harsi_zone` VARCHAR(10) NULL,
  `sma_delta` DECIMAL(12,2) NULL,
  `sma_delta_avg` DECIMAL(12,2) NULL,
  `sma_delta_trend` VARCHAR(10) NULL,
  `lo_delta_flow_pct` DOUBLE NULL,
  `lo_delta_signal` VARCHAR(10) NULL,
  `combined_signal` VARCHAR(10) NULL,
  `combined_signal_ind` VARCHAR(10) NULL,
  `volume` BIGINT UNSIGNED NULL,
  `volume_expansion_pct` DECIMAL(10,2) NULL,
  `predicted_5bar_return_pct` DECIMAL(10,2) NULL,
  `predicted_10bar_return_pct` DECIMAL(10,2) NULL,
  `risk_note` VARCHAR(500) NULL,
  `generated_at` DATETIME NOT NULL,
  PRIMARY KEY (`symbol`, `frequency`, `signal_date`),
  KEY `ix_momentum_frequency_score` (`frequency`, `momentum_direction`, `momentum_score`),
  KEY `ix_momentum_phase` (`frequency`, `momentum_phase`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP PROCEDURE IF EXISTS `reco_momentum_refresh`;

CREATE PROCEDURE `reco_momentum_refresh`()
BEGIN
  DECLARE v_generated_at DATETIME DEFAULT NOW();

  CREATE TABLE IF NOT EXISTS `jstockdata_momentum_signal` (
    `symbol` VARCHAR(20) NOT NULL,
    `frequency` VARCHAR(20) NOT NULL,
    `signal_date` INT NOT NULL,
    `close_price` DECIMAL(12,2) NULL,
    `momentum_score` DECIMAL(8,2) NULL,
    `momentum_direction` VARCHAR(12) NOT NULL,
    `momentum_phase` VARCHAR(20) NOT NULL,
    `momentum_confidence_pct` DECIMAL(6,2) NULL,
    `momentum_age_bars` INT NULL,
    `momentum_acceleration` DECIMAL(10,2) NULL,
    `momentum_exhaustion_score` DECIMAL(8,2) NULL,
    `momentum_reversal_risk_pct` DECIMAL(6,2) NULL,
    `close_change_3bar_pct` DECIMAL(10,2) NULL,
    `close_change_5bar_pct` DECIMAL(10,2) NULL,
    `ha_change_pct` DECIMAL(10,2) NULL,
    `ha_change_3bar_delta` DECIMAL(10,2) NULL,
    `ha_trend_correct` VARCHAR(10) NULL,
    `ha_trend_signal` VARCHAR(10) NULL,
    `ha_strong_signal` VARCHAR(15) NULL,
    `ha_rally_seq` INT NULL,
    `ha_rally_slope` DECIMAL(12,2) NULL,
    `ha_rally_angle` DECIMAL(12,2) NULL,
    `harsi_value` DECIMAL(12,2) NULL,
    `harsi_zone` VARCHAR(10) NULL,
    `sma_delta` DECIMAL(12,2) NULL,
    `sma_delta_avg` DECIMAL(12,2) NULL,
    `sma_delta_trend` VARCHAR(10) NULL,
    `lo_delta_flow_pct` DOUBLE NULL,
    `lo_delta_signal` VARCHAR(10) NULL,
    `combined_signal` VARCHAR(10) NULL,
    `combined_signal_ind` VARCHAR(10) NULL,
    `volume` BIGINT UNSIGNED NULL,
    `volume_expansion_pct` DECIMAL(10,2) NULL,
    `predicted_5bar_return_pct` DECIMAL(10,2) NULL,
    `predicted_10bar_return_pct` DECIMAL(10,2) NULL,
    `risk_note` VARCHAR(500) NULL,
    `generated_at` DATETIME NOT NULL,
    PRIMARY KEY (`symbol`, `frequency`, `signal_date`),
    KEY `ix_momentum_frequency_score` (`frequency`, `momentum_direction`, `momentum_score`),
    KEY `ix_momentum_phase` (`frequency`, `momentum_phase`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

  TRUNCATE TABLE `jstockdata_momentum_signal`;

  DROP TABLE IF EXISTS `jstockdata_momentum_work_base`;
  CREATE TABLE `jstockdata_momentum_work_base` AS
  SELECT
    ordered.*,
    @row_num := IF(@row_key = CONCAT(ordered.symbol, '|', ordered.frequency), @row_num + 1, 1) AS seq_num,
    @row_key := CONCAT(ordered.symbol, '|', ordered.frequency) AS seq_key
  FROM (
    SELECT
      h.`SCRIP` AS symbol,
      TRIM(REPLACE(h.`Frequency`, '\r', '')) AS frequency,
      h.`DATE` AS signal_date,
      h.`CLOSE` AS close_price,
      h.`volume`,
      h.`HATrendCorrect`,
      h.`HATrendSignal`,
      h.`HAStrongSignal`,
      h.`HAChangePct`,
      h.`HAIndex`,
      h.`HARunIndex`,
      h.`HARallySeq`,
      h.`HARallySlope`,
      h.`HARallyAngle`,
      e.`SMAValue1`,
      e.`SMAValue2`,
      e.`SMADelta`,
      e.`SMADeltaAvg`,
      e.`SMADeltaTrend`,
      e.`HARSIValue`,
      e.`HARSIZone`,
      e.`LODeltaFlowPct`,
      e.`LODeltaSignal`,
      e.`Combined_Signal`,
      e.`Combined_Signal_Ind`
    FROM `jstockdata_harecent` h
    JOIN `jstockdata_harecent_extend` e
      ON e.`SCRIP` = h.`SCRIP`
     AND e.`DATE` = h.`DATE`
     AND TRIM(REPLACE(e.`FREQUENCY`, '\r', '')) = TRIM(REPLACE(h.`Frequency`, '\r', ''))
    WHERE TRIM(REPLACE(h.`Frequency`, '\r', '')) IN ('DAILY', 'WEEKLY')
    ORDER BY h.`SCRIP`, TRIM(REPLACE(h.`Frequency`, '\r', '')), h.`DATE`
  ) ordered
  CROSS JOIN (SELECT @row_key := '', @row_num := 0) vars;

  ALTER TABLE `jstockdata_momentum_work_base`
    ADD PRIMARY KEY (`symbol`, `frequency`, `seq_num`),
    ADD KEY `ix_tmp_momentum_latest` (`symbol`, `frequency`, `signal_date`);

  DROP TEMPORARY TABLE IF EXISTS `tmp_momentum_calc`;
  CREATE TEMPORARY TABLE `tmp_momentum_calc` AS
  SELECT
    b.*,
    CASE WHEN p3.close_price > 0 THEN ROUND((b.close_price - p3.close_price) / p3.close_price * 100, 2) END AS close_change_3bar_pct,
    CASE WHEN p5.close_price > 0 THEN ROUND((b.close_price - p5.close_price) / p5.close_price * 100, 2) END AS close_change_5bar_pct,
    ROUND(b.HAChangePct - COALESCE(p3.HAChangePct, b.HAChangePct), 2) AS ha_change_3bar_delta,
    ROUND(b.HAChangePct - ((COALESCE(p1.HAChangePct, b.HAChangePct) + COALESCE(p2.HAChangePct, b.HAChangePct) + COALESCE(p3.HAChangePct, b.HAChangePct)) / 3), 2) AS momentum_acceleration,
    CASE
      WHEN (COALESCE(p1.volume, 0) + COALESCE(p2.volume, 0) + COALESCE(p3.volume, 0) + COALESCE(p4.volume, 0) + COALESCE(p5.volume, 0)) > 0
      THEN ROUND((b.volume / ((COALESCE(p1.volume, 0) + COALESCE(p2.volume, 0) + COALESCE(p3.volume, 0) + COALESCE(p4.volume, 0) + COALESCE(p5.volume, 0)) / 5) - 1) * 100, 2)
    END AS volume_expansion_pct,
    (
      CASE WHEN b.HATrendCorrect = 'GREEN' THEN 18 WHEN b.HATrendCorrect = 'RED' THEN -18 ELSE 0 END
      + CASE WHEN b.HATrendSignal = 'BUY' THEN 12 WHEN b.HATrendSignal = 'SELL' THEN -12 ELSE 0 END
      + CASE WHEN b.HAStrongSignal = 'STRONG BUY' THEN 12 WHEN b.HAStrongSignal = 'STRONG SELL' THEN -12 ELSE 0 END
      + CASE WHEN b.Combined_Signal = 'BUY' THEN 14 WHEN b.Combined_Signal = 'SELL' THEN -14 ELSE 0 END
      + CASE WHEN b.Combined_Signal_Ind = 'BUY' THEN 8 WHEN b.Combined_Signal_Ind = 'SELL' THEN -8 ELSE 0 END
      + CASE WHEN b.SMADeltaTrend = 'UP' THEN 10 WHEN b.SMADeltaTrend = 'DOWN' THEN -10 ELSE 0 END
      + CASE WHEN b.LODeltaSignal = 'BUY' THEN 10 WHEN b.LODeltaSignal = 'SELL' THEN -10 ELSE 0 END
      + LEAST(12, GREATEST(-12, COALESCE(b.HAChangePct, 0) * 2))
      + LEAST(10, GREATEST(-10, COALESCE(b.HARallySlope, 0) / 2))
      + LEAST(8, GREATEST(-8, COALESCE(b.HARallyAngle, 0) / 6))
      + CASE
          WHEN b.HARSIValue BETWEEN 45 AND 70 THEN 7
          WHEN b.HARSIValue BETWEEN 30 AND 45 THEN 2
          WHEN b.HARSIValue > 80 THEN -4
          WHEN b.HARSIValue < 20 THEN -4
          ELSE 0
        END
      + CASE
          WHEN b.LODeltaFlowPct > 0 THEN LEAST(8, b.LODeltaFlowPct / 5)
          WHEN b.LODeltaFlowPct < 0 THEN GREATEST(-8, b.LODeltaFlowPct / 5)
          ELSE 0
        END
    ) AS raw_momentum_score
  FROM `jstockdata_momentum_work_base` b
  LEFT JOIN `jstockdata_momentum_work_base` p1 ON p1.symbol = b.symbol AND p1.frequency = b.frequency AND p1.seq_num = b.seq_num - 1
  LEFT JOIN `jstockdata_momentum_work_base` p2 ON p2.symbol = b.symbol AND p2.frequency = b.frequency AND p2.seq_num = b.seq_num - 2
  LEFT JOIN `jstockdata_momentum_work_base` p3 ON p3.symbol = b.symbol AND p3.frequency = b.frequency AND p3.seq_num = b.seq_num - 3
  LEFT JOIN `jstockdata_momentum_work_base` p4 ON p4.symbol = b.symbol AND p4.frequency = b.frequency AND p4.seq_num = b.seq_num - 4
  LEFT JOIN `jstockdata_momentum_work_base` p5 ON p5.symbol = b.symbol AND p5.frequency = b.frequency AND p5.seq_num = b.seq_num - 5;

  INSERT INTO `jstockdata_momentum_signal` (
    symbol, frequency, signal_date, close_price, momentum_score, momentum_direction,
    momentum_phase, momentum_confidence_pct, momentum_age_bars, momentum_acceleration,
    momentum_exhaustion_score, momentum_reversal_risk_pct, close_change_3bar_pct,
    close_change_5bar_pct, ha_change_pct, ha_change_3bar_delta, ha_trend_correct,
    ha_trend_signal, ha_strong_signal, ha_rally_seq, ha_rally_slope, ha_rally_angle,
    harsi_value, harsi_zone, sma_delta, sma_delta_avg, sma_delta_trend,
    lo_delta_flow_pct, lo_delta_signal, combined_signal, combined_signal_ind,
    volume, volume_expansion_pct, predicted_5bar_return_pct, predicted_10bar_return_pct,
    risk_note, generated_at
  )
  SELECT
    c.symbol,
    c.frequency,
    c.signal_date,
    c.close_price,
    ROUND(LEAST(100, GREATEST(-100, c.raw_momentum_score)), 2) AS momentum_score,
    CASE
      WHEN c.raw_momentum_score >= 18 THEN 'BULLISH'
      WHEN c.raw_momentum_score <= -18 THEN 'BEARISH'
      ELSE 'NEUTRAL'
    END AS momentum_direction,
    CASE
      WHEN c.raw_momentum_score >= 18
           AND COALESCE(c.HARallySeq, 0) BETWEEN 1 AND 3
           AND COALESCE(c.momentum_acceleration, 0) > 0 THEN 'EARLY'
      WHEN c.raw_momentum_score >= 18
           AND COALESCE(c.momentum_acceleration, 0) > 0
           AND COALESCE(c.HARSIValue, 50) < 75 THEN 'ACCELERATING'
      WHEN c.raw_momentum_score >= 18
           AND (COALESCE(c.HARSIValue, 50) >= 75 OR COALESCE(c.HARallySeq, 0) >= 8) THEN 'MATURE'
      WHEN c.raw_momentum_score >= 18
           AND COALESCE(c.momentum_acceleration, 0) < 0 THEN 'WEAKENING'
      WHEN c.raw_momentum_score <= -18
           AND COALESCE(c.momentum_acceleration, 0) < 0 THEN 'ACCELERATING'
      WHEN ABS(c.raw_momentum_score) < 18 THEN 'NEUTRAL'
      ELSE 'REVERSAL_RISK'
    END AS momentum_phase,
    ROUND(LEAST(100, GREATEST(0,
      ABS(c.raw_momentum_score) * 0.65
      + CASE WHEN c.Combined_Signal IN ('BUY', 'SELL') THEN 10 ELSE 0 END
      + CASE WHEN c.Combined_Signal_Ind IN ('BUY', 'SELL') THEN 8 ELSE 0 END
      + CASE WHEN ABS(COALESCE(c.momentum_acceleration, 0)) >= 1 THEN 5 ELSE 0 END
      + CASE WHEN COALESCE(c.volume_expansion_pct, 0) > 20 THEN 5 ELSE 0 END
    )), 2) AS momentum_confidence_pct,
    ABS(COALESCE(c.HARallySeq, 0)) AS momentum_age_bars,
    c.momentum_acceleration,
    ROUND(LEAST(100, GREATEST(0,
      CASE WHEN c.HARSIValue >= 80 OR c.HARSIValue <= 20 THEN 25 ELSE 0 END
      + CASE WHEN ABS(COALESCE(c.HARallySeq, 0)) >= 8 THEN 20 ELSE 0 END
      + CASE WHEN ABS(COALESCE(c.HARallyAngle, 0)) >= 60 THEN 15 ELSE 0 END
      + CASE WHEN c.raw_momentum_score >= 18 AND COALESCE(c.momentum_acceleration, 0) < 0 THEN 20 ELSE 0 END
      + CASE WHEN c.raw_momentum_score <= -18 AND COALESCE(c.momentum_acceleration, 0) > 0 THEN 20 ELSE 0 END
      + CASE WHEN c.Combined_Signal_Ind IN ('BUY', 'SELL') THEN 5 ELSE 0 END
    )), 2) AS momentum_exhaustion_score,
    ROUND(LEAST(100, GREATEST(0,
      CASE WHEN c.HARSIValue >= 80 OR c.HARSIValue <= 20 THEN 20 ELSE 0 END
      + CASE WHEN ABS(COALESCE(c.HARallySeq, 0)) >= 8 THEN 15 ELSE 0 END
      + CASE WHEN c.raw_momentum_score >= 18 AND c.LODeltaSignal = 'SELL' THEN 25 ELSE 0 END
      + CASE WHEN c.raw_momentum_score <= -18 AND c.LODeltaSignal = 'BUY' THEN 25 ELSE 0 END
      + CASE WHEN c.raw_momentum_score >= 18 AND COALESCE(c.momentum_acceleration, 0) < 0 THEN 20 ELSE 0 END
      + CASE WHEN c.raw_momentum_score <= -18 AND COALESCE(c.momentum_acceleration, 0) > 0 THEN 20 ELSE 0 END
      + CASE WHEN c.raw_momentum_score >= 18 AND c.HATrendSignal = 'SELL' THEN 20 ELSE 0 END
      + CASE WHEN c.raw_momentum_score <= -18 AND c.HATrendSignal = 'BUY' THEN 20 ELSE 0 END
    )), 2) AS momentum_reversal_risk_pct,
    c.close_change_3bar_pct,
    c.close_change_5bar_pct,
    c.HAChangePct,
    c.ha_change_3bar_delta,
    c.HATrendCorrect,
    c.HATrendSignal,
    c.HAStrongSignal,
    c.HARallySeq,
    c.HARallySlope,
    c.HARallyAngle,
    c.HARSIValue,
    c.HARSIZone,
    c.SMADelta,
    c.SMADeltaAvg,
    c.SMADeltaTrend,
    c.LODeltaFlowPct,
    c.LODeltaSignal,
    c.Combined_Signal,
    c.Combined_Signal_Ind,
    c.volume,
    c.volume_expansion_pct,
    ROUND(
      LEAST(6, GREATEST(-6,
        COALESCE(c.close_change_3bar_pct, 0) * 0.35
        + COALESCE(c.HAChangePct, 0) * 0.30
        + COALESCE(c.momentum_acceleration, 0) * 0.20
        + LEAST(2, GREATEST(-2, c.raw_momentum_score / 35))
      )), 2
    ) AS predicted_5bar_return_pct,
    ROUND(
      LEAST(10, GREATEST(-10,
        COALESCE(c.close_change_5bar_pct, 0) * 0.35
        + COALESCE(c.HAChangePct, 0) * 0.45
        + COALESCE(c.momentum_acceleration, 0) * 0.25
        + LEAST(3, GREATEST(-3, c.raw_momentum_score / 30))
      )), 2
    ) AS predicted_10bar_return_pct,
    CASE
      WHEN c.raw_momentum_score >= 18 AND (c.HARSIValue >= 80 OR ABS(COALESCE(c.HARallySeq, 0)) >= 8) THEN 'Bullish momentum but extended; prefer smaller size or profit-lock review.'
      WHEN c.raw_momentum_score >= 18 AND c.LODeltaSignal = 'SELL' THEN 'Bullish score with opposing LODeltaSignal; watch for reversal.'
      WHEN c.raw_momentum_score <= -18 AND c.LODeltaSignal = 'BUY' THEN 'Bearish score with opposing LODeltaSignal; avoid aggressive short bias.'
      WHEN ABS(c.raw_momentum_score) < 18 THEN 'Momentum neutral; wait for stronger confirmation.'
      ELSE 'Momentum aligned.'
    END AS risk_note,
    v_generated_at
  FROM `tmp_momentum_calc` c;

  DROP TABLE IF EXISTS `jstockdata_momentum_work_base`;

  CALL reco_runlog_mark('reco_momentum_refresh', 'SUCCESS',
                        CONCAT('Generated momentum rows at ', v_generated_at));
END;

DROP PROCEDURE IF EXISTS `reco_weekly_projection_refresh`;

CREATE PROCEDURE `reco_weekly_projection_refresh`()
BEGIN
  DECLARE v_started_at datetime DEFAULT NOW();
  DECLARE v_current_step varchar(128) DEFAULT 'reco_weekly_projection_refresh';

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    CALL reco_runlog_mark(v_current_step, 'FAILED', 'Failed during reco_weekly_projection_refresh');
    CALL reco_runlog_mark('reco_weekly_projection_refresh', 'FAILED', CONCAT('Failed wrapper; started at ', v_started_at));
    RESIGNAL;
  END;

  SET v_current_step = 'reco_backtest';
  CALL reco_backtest();
  CALL reco_runlog_mark('reco_backtest', 'SUCCESS', 'Completed by reco_weekly_projection_refresh');

  SET v_current_step = 'reco_trade';
  CALL reco_trade();
  CALL reco_runlog_mark('reco_trade', 'SUCCESS', 'Completed by reco_weekly_projection_refresh');

  SET v_current_step = 'reco_invest';
  CALL reco_invest();
  CALL reco_runlog_mark('reco_invest', 'SUCCESS', 'Completed by reco_weekly_projection_refresh');

  SET v_current_step = 'reco_options';
  CALL reco_options();
  CALL reco_runlog_mark('reco_options', 'SUCCESS', 'Completed by reco_weekly_projection_refresh');

  SET v_current_step = 'reco_projection_refresh';
  CALL reco_projection_refresh();
  CALL reco_runlog_mark('reco_projection_refresh', 'SUCCESS', 'Completed by reco_weekly_projection_refresh');

  SET v_current_step = 'reco_projection_enrich_outputs';
  CALL reco_projection_enrich_outputs();
  CALL reco_runlog_mark('reco_projection_enrich_outputs', 'SUCCESS', 'Completed by reco_weekly_projection_refresh');

  SET v_current_step = 'reco_momentum_refresh';
  CALL reco_momentum_refresh();
  CALL reco_runlog_mark('reco_momentum_refresh', 'SUCCESS', 'Completed by reco_weekly_projection_refresh');

  SET v_current_step = 'reco_basket_refresh';
  CALL reco_basket_refresh();
  CALL reco_runlog_mark('reco_basket_refresh', 'SUCCESS', 'Completed by reco_weekly_projection_refresh');

  SET v_current_step = 'reco_weekly_target_refresh';
  CALL reco_weekly_target_refresh();
  CALL reco_runlog_mark('reco_weekly_target_refresh', 'SUCCESS', 'Completed by reco_weekly_projection_refresh');

  CALL reco_runlog_mark('reco_weekly_projection_refresh', 'SUCCESS', CONCAT('Completed wrapper; started at ', v_started_at));
END;
