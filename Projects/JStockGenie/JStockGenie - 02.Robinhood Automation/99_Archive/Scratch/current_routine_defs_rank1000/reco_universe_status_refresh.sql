CREATE DEFINER=`admin`@`%` PROCEDURE `reco_universe_status_refresh`(IN p_keep_limit INT)
BEGIN
  DECLARE v_generated_at DATETIME DEFAULT NOW();
  DECLARE v_keep_limit INT DEFAULT 1000;
  DECLARE v_min_rank DOUBLE DEFAULT 0;
  DECLARE v_max_rank DOUBLE DEFAULT 0;
  DECLARE v_liq_count INT DEFAULT 0;

  IF p_keep_limit IS NOT NULL AND p_keep_limit > 0 THEN
    SET v_keep_limit = p_keep_limit;
  END IF;

  CREATE TABLE IF NOT EXISTS `jstockdata_reco_universe_score` (
    `generated_at` DATETIME NOT NULL,
    `keep_limit` INT NOT NULL,
    `universe_rank` INT NOT NULL,
    `scrip` VARCHAR(20) NOT NULL,
    `assetclass` VARCHAR(30) NOT NULL,
    `source_rank` INT NULL,
    `universe_score` DECIMAL(10,4) NOT NULL,
    `trend_component` DECIMAL(10,4) NOT NULL,
    `momentum_component` DECIMAL(10,4) NOT NULL,
    `source_rank_score` DECIMAL(10,4) NOT NULL,
    `liquidity_score` DECIMAL(10,4) NOT NULL,
    `latest_close_price` DECIMAL(12,2) NULL,
    `latest_volume` BIGINT UNSIGNED NULL,
    `latest_dollar_volume` DECIMAL(20,2) NULL,
    `reco_universe_status` VARCHAR(10) NOT NULL,
    PRIMARY KEY (`generated_at`, `scrip`),
    KEY `ix_universe_score_status` (`reco_universe_status`, `assetclass`, `universe_rank`),
    KEY `ix_universe_score_scrip` (`scrip`, `generated_at`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

  DROP TEMPORARY TABLE IF EXISTS tmp_reco_universe;
  CREATE TEMPORARY TABLE tmp_reco_universe AS
  SELECT
    s.`Scrip` AS scrip,
    UPPER(TRIM(s.`AssetClass`)) AS assetclass,
    MIN(s.`Rank`) AS source_rank
  FROM `jstockdata_scrips` s
  WHERE UPPER(TRIM(s.`AssetClass`)) IN ('EQ', 'ETF')
    AND s.`Scrip` IS NOT NULL
  GROUP BY s.`Scrip`, UPPER(TRIM(s.`AssetClass`));
  ALTER TABLE tmp_reco_universe ADD PRIMARY KEY (`scrip`);

  SELECT MIN(source_rank), MAX(source_rank)
    INTO v_min_rank, v_max_rank
  FROM tmp_reco_universe
  WHERE source_rank IS NOT NULL;

  DROP TEMPORARY TABLE IF EXISTS tmp_universe_latest_extend;
  CREATE TEMPORARY TABLE tmp_universe_latest_extend AS
  SELECT
    e.`SCRIP` AS scrip,
    TRIM(REPLACE(e.`FREQUENCY`, '\r', '')) AS frequency,
    e.`DATE` AS signal_date,
    e.`Close` AS close_price,
    UPPER(TRIM(COALESCE(e.`Combined_Signal`, ''))) AS combined_signal,
    UPPER(TRIM(COALESCE(e.`Combined_Signal_Ind`, ''))) AS combined_signal_ind,
    UPPER(TRIM(COALESCE(e.`LODeltaSignal`, ''))) AS lo_delta_signal,
    UPPER(TRIM(COALESCE(e.`SMADeltaTrend`, ''))) AS sma_delta_trend,
    e.`HARSIValue` AS harsi_value
  FROM `jstockdata_hatrend_extend` e
  JOIN (
    SELECT
      TRIM(REPLACE(`FREQUENCY`, '\r', '')) AS frequency,
      MAX(`DATE`) AS max_date
    FROM `jstockdata_hatrend_extend`
    WHERE TRIM(REPLACE(`FREQUENCY`, '\r', '')) IN ('DAILY', 'WEEKLY')
    GROUP BY TRIM(REPLACE(`FREQUENCY`, '\r', ''))
  ) latest
    ON latest.frequency = TRIM(REPLACE(e.`FREQUENCY`, '\r', ''))
   AND latest.max_date = e.`DATE`
  JOIN tmp_reco_universe u ON u.scrip = e.`SCRIP`
  WHERE TRIM(REPLACE(e.`FREQUENCY`, '\r', '')) IN ('DAILY', 'WEEKLY')
    AND e.`Close` > 0;
  ALTER TABLE tmp_universe_latest_extend ADD PRIMARY KEY (`scrip`, `frequency`);

  DROP TEMPORARY TABLE IF EXISTS tmp_universe_trend_score;
  CREATE TEMPORARY TABLE tmp_universe_trend_score AS
  SELECT
    scrip,
    frequency,
    LEAST(100, GREATEST(0,
      50
      + CASE combined_signal WHEN 'BUY' THEN 18 WHEN 'SELL' THEN -18 ELSE 0 END
      + CASE combined_signal_ind WHEN 'BUY' THEN 10 WHEN 'SELL' THEN -10 ELSE 0 END
      + CASE lo_delta_signal WHEN 'BUY' THEN 10 WHEN 'SELL' THEN -10 ELSE 0 END
      + CASE sma_delta_trend WHEN 'UP' THEN 7 WHEN 'DOWN' THEN -7 ELSE 0 END
      + CASE
          WHEN harsi_value >= 75 THEN -4
          WHEN harsi_value <= 25 THEN -6
          WHEN harsi_value BETWEEN 45 AND 65 THEN 3
          ELSE 0
        END
    )) AS trend_score
  FROM tmp_universe_latest_extend;
  ALTER TABLE tmp_universe_trend_score ADD PRIMARY KEY (`scrip`, `frequency`);

  DROP TEMPORARY TABLE IF EXISTS tmp_universe_recent_raw;
  CREATE TEMPORARY TABLE tmp_universe_recent_raw AS
  SELECT
    h.`SCRIP` AS scrip,
    TRIM(REPLACE(h.`Frequency`, '\r', '')) AS frequency,
    h.`DATE` AS signal_date,
    h.`CLOSE` AS close_price,
    h.`volume`,
    UPPER(TRIM(COALESCE(h.`HATrendCorrect`, ''))) AS ha_trend_correct,
    UPPER(TRIM(COALESCE(h.`HATrendSignal`, ''))) AS ha_trend_signal,
    UPPER(TRIM(COALESCE(h.`HAStrongSignal`, ''))) AS ha_strong_signal,
    h.`HAChangePct` AS ha_change_pct,
    h.`HARallySlope` AS ha_rally_slope,
    h.`HARallyAngle` AS ha_rally_angle,
    UPPER(TRIM(COALESCE(e.`Combined_Signal`, ''))) AS combined_signal,
    UPPER(TRIM(COALESCE(e.`Combined_Signal_Ind`, ''))) AS combined_signal_ind,
    UPPER(TRIM(COALESCE(e.`LODeltaSignal`, ''))) AS lo_delta_signal,
    UPPER(TRIM(COALESCE(e.`SMADeltaTrend`, ''))) AS sma_delta_trend,
    e.`HARSIValue` AS harsi_value
  FROM `jstockdata_harecent` h
  JOIN (
    SELECT
      TRIM(REPLACE(`Frequency`, '\r', '')) AS frequency,
      MAX(`DATE`) AS max_date
    FROM `jstockdata_harecent`
    WHERE TRIM(REPLACE(`Frequency`, '\r', '')) IN ('DAILY', 'WEEKLY')
    GROUP BY TRIM(REPLACE(`Frequency`, '\r', ''))
  ) latest
    ON latest.frequency = TRIM(REPLACE(h.`Frequency`, '\r', ''))
   AND latest.max_date = h.`DATE`
  JOIN `jstockdata_harecent_extend` e
    ON e.`SCRIP` = h.`SCRIP`
   AND e.`DATE` = h.`DATE`
   AND TRIM(REPLACE(e.`FREQUENCY`, '\r', '')) = TRIM(REPLACE(h.`Frequency`, '\r', ''))
  JOIN tmp_reco_universe u ON u.scrip = h.`SCRIP`
  WHERE TRIM(REPLACE(h.`Frequency`, '\r', '')) IN ('DAILY', 'WEEKLY')
    AND h.`CLOSE` > 0;
  ALTER TABLE tmp_universe_recent_raw ADD PRIMARY KEY (`scrip`, `frequency`);

  DROP TEMPORARY TABLE IF EXISTS tmp_universe_momentum_score;
  CREATE TEMPORARY TABLE tmp_universe_momentum_score AS
  SELECT
    scrip,
    frequency,
    LEAST(100, GREATEST(0,
      50
      + CASE ha_trend_correct WHEN 'GREEN' THEN 10 WHEN 'RED' THEN -10 ELSE 0 END
      + CASE ha_trend_signal WHEN 'BUY' THEN 8 WHEN 'SELL' THEN -8 ELSE 0 END
      + CASE ha_strong_signal WHEN 'STRONG BUY' THEN 8 WHEN 'STRONG SELL' THEN -8 ELSE 0 END
      + CASE combined_signal WHEN 'BUY' THEN 12 WHEN 'SELL' THEN -12 ELSE 0 END
      + CASE combined_signal_ind WHEN 'BUY' THEN 6 WHEN 'SELL' THEN -6 ELSE 0 END
      + CASE sma_delta_trend WHEN 'UP' THEN 8 WHEN 'DOWN' THEN -8 ELSE 0 END
      + CASE lo_delta_signal WHEN 'BUY' THEN 8 WHEN 'SELL' THEN -8 ELSE 0 END
      + LEAST(8, GREATEST(-8, COALESCE(ha_change_pct, 0) * 2))
      + LEAST(6, GREATEST(-6, COALESCE(ha_rally_slope, 0) / 2))
      + LEAST(5, GREATEST(-5, COALESCE(ha_rally_angle, 0) / 6))
      + CASE
          WHEN harsi_value BETWEEN 45 AND 68 THEN 4
          WHEN harsi_value > 78 THEN -6
          WHEN harsi_value < 25 THEN -8
          ELSE 0
        END
    )) AS raw_momentum_score
  FROM tmp_universe_recent_raw;
  ALTER TABLE tmp_universe_momentum_score ADD PRIMARY KEY (`scrip`, `frequency`);

  DROP TEMPORARY TABLE IF EXISTS tmp_universe_ohlcv;
  CREATE TEMPORARY TABLE tmp_universe_ohlcv AS
  SELECT
    h.`SCRIP` AS scrip,
    h.`CLOSE` AS latest_close_price,
    h.`volume` AS latest_volume,
    h.`CLOSE` * h.`volume` AS latest_dollar_volume
  FROM `jstockdata_hatrend` h
  JOIN (
    SELECT MAX(`DATE`) AS max_date
    FROM `jstockdata_hatrend`
    WHERE TRIM(REPLACE(`Frequency`, '\r', '')) = 'DAILY'
  ) latest ON latest.max_date = h.`DATE`
  JOIN tmp_reco_universe u ON u.scrip = h.`SCRIP`
  WHERE TRIM(REPLACE(h.`Frequency`, '\r', '')) = 'DAILY'
    AND h.`CLOSE` > 0;
  ALTER TABLE tmp_universe_ohlcv ADD PRIMARY KEY (`scrip`);

  DROP TEMPORARY TABLE IF EXISTS tmp_universe_liquidity_rank;
  CREATE TEMPORARY TABLE tmp_universe_liquidity_rank AS
  SELECT
    ranked.scrip,
    ranked.latest_close_price,
    ranked.latest_volume,
    ranked.latest_dollar_volume,
    ranked.liq_rank
  FROM (
    SELECT
      o.*,
      @liq_rank := @liq_rank + 1 AS liq_rank
    FROM (
      SELECT *
      FROM tmp_universe_ohlcv
      ORDER BY latest_dollar_volume, scrip
    ) o
    CROSS JOIN (SELECT @liq_rank := 0) vars
  ) ranked;
  ALTER TABLE tmp_universe_liquidity_rank ADD PRIMARY KEY (`scrip`);

  SELECT COUNT(*) INTO v_liq_count FROM tmp_universe_liquidity_rank;

  DROP TEMPORARY TABLE IF EXISTS tmp_universe_scored;
  CREATE TEMPORARY TABLE tmp_universe_scored AS
  SELECT
    u.scrip,
    u.assetclass,
    u.source_rank,
    (
      COALESCE(MAX(CASE WHEN ts.frequency = 'DAILY' THEN ts.trend_score END), 50) * 0.40
      + COALESCE(MAX(CASE WHEN ts.frequency = 'WEEKLY' THEN ts.trend_score END), 50) * 0.60
    ) AS trend_component,
    (
      COALESCE(MAX(CASE WHEN ms.frequency = 'DAILY' THEN ms.raw_momentum_score END), 50) * 0.45
      + COALESCE(MAX(CASE WHEN ms.frequency = 'WEEKLY' THEN ms.raw_momentum_score END), 50) * 0.55
    ) AS momentum_component,
    CASE
      WHEN u.source_rank IS NULL OR v_max_rank = v_min_rank THEN 50
      ELSE 100 - ((u.source_rank - v_min_rank) / NULLIF(v_max_rank - v_min_rank, 0) * 100)
    END AS source_rank_score,
    CASE
      WHEN lr.scrip IS NULL OR v_liq_count <= 1 THEN 50
      ELSE (lr.liq_rank - 1) / NULLIF(v_liq_count - 1, 0) * 100
    END AS liquidity_score,
    lr.latest_close_price,
    lr.latest_volume,
    lr.latest_dollar_volume
  FROM tmp_reco_universe u
  LEFT JOIN tmp_universe_trend_score ts ON ts.scrip = u.scrip
  LEFT JOIN tmp_universe_momentum_score ms ON ms.scrip = u.scrip
  LEFT JOIN tmp_universe_liquidity_rank lr ON lr.scrip = u.scrip
  GROUP BY
    u.scrip, u.assetclass, u.source_rank,
    lr.scrip, lr.liq_rank, lr.latest_close_price, lr.latest_volume, lr.latest_dollar_volume;
  ALTER TABLE tmp_universe_scored ADD PRIMARY KEY (`scrip`);

  DROP TEMPORARY TABLE IF EXISTS tmp_universe_ranked;
  CREATE TEMPORARY TABLE tmp_universe_ranked AS
  SELECT
    ranked.*,
    IF(ranked.universe_rank <= v_keep_limit, 'KEEP', 'OMIT') AS reco_universe_status
  FROM (
    SELECT
      scored.*,
      (
        scored.trend_component * 0.38
        + scored.momentum_component * 0.42
        + scored.source_rank_score * 0.12
        + scored.liquidity_score * 0.08
      ) AS universe_score,
      @universe_rank := @universe_rank + 1 AS universe_rank
    FROM (
      SELECT *
      FROM tmp_universe_scored
      ORDER BY
        (trend_component * 0.38 + momentum_component * 0.42 + source_rank_score * 0.12 + liquidity_score * 0.08) DESC,
        source_rank_score DESC,
        liquidity_score DESC,
        scrip
    ) scored
    CROSS JOIN (SELECT @universe_rank := 0) vars
  ) ranked;
  ALTER TABLE tmp_universe_ranked ADD PRIMARY KEY (`scrip`);

  UPDATE `jstockdata_scrips`
  SET
    `RecoUniverseStatus` = 'OMIT',
    `RecoUniverseRank` = NULL;

  UPDATE `jstockdata_scrips` s
  JOIN tmp_universe_ranked r ON r.scrip = s.`Scrip`
  SET
    s.`RecoUniverseStatus` = r.reco_universe_status,
    s.`RecoUniverseRank` = r.universe_rank;

  DELETE FROM `jstockdata_reco_universe_score`
  WHERE generated_at < DATE_SUB(v_generated_at, INTERVAL 180 DAY);

  INSERT INTO `jstockdata_reco_universe_score` (
    generated_at, keep_limit, universe_rank, scrip, assetclass, source_rank,
    universe_score, trend_component, momentum_component, source_rank_score,
    liquidity_score, latest_close_price, latest_volume, latest_dollar_volume,
    reco_universe_status
  )
  SELECT
    v_generated_at, v_keep_limit, universe_rank, scrip, assetclass, source_rank,
    ROUND(universe_score, 4), ROUND(trend_component, 4), ROUND(momentum_component, 4),
    ROUND(source_rank_score, 4), ROUND(liquidity_score, 4),
    latest_close_price, latest_volume, latest_dollar_volume, reco_universe_status
  FROM tmp_universe_ranked;

  CALL reco_runlog_mark(
    'reco_universe_status_refresh',
    'SUCCESS',
    CONCAT('Updated RecoUniverseStatus for top ', v_keep_limit, ' EQ/ETF scrips at ', v_generated_at)
  );
END