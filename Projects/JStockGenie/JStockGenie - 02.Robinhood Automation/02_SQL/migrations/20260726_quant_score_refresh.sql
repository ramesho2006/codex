-- Rename and refine the active universe scoring table into a Quant-style score.
--
-- The score is not a clone of Seeking Alpha's proprietary Quant Rating. It is a
-- JStockGenie technical/projection quant score built from data already available
-- in MySQL: trend, momentum, projection, backtest, liquidity/source quality, and
-- news/risk signals.

SET @old_table_exists := (
  SELECT COUNT(*)
  FROM information_schema.tables
  WHERE table_schema = DATABASE()
    AND table_name = 'jstockdata_reco_universe_score'
);

SET @new_table_exists := (
  SELECT COUNT(*)
  FROM information_schema.tables
  WHERE table_schema = DATABASE()
    AND table_name = 'jstockdata_reco_quant_score'
);

SET @rename_sql := IF(
  @old_table_exists > 0 AND @new_table_exists = 0,
  'RENAME TABLE jstockdata_reco_universe_score TO jstockdata_reco_quant_score',
  'SELECT ''quant score table already migrated'' AS migration_note'
);
PREPARE stmt FROM @rename_sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DROP TABLE IF EXISTS `jstockdata_reco_universe_score`;

DROP PROCEDURE IF EXISTS `reco_universe_status_refresh`;

DELIMITER $$
CREATE PROCEDURE `reco_universe_status_refresh`(IN p_keep_limit INT)
BEGIN
  DECLARE v_generated_at DATETIME DEFAULT NOW();
  DECLARE v_keep_limit INT DEFAULT 1000;
  DECLARE v_min_rank DOUBLE DEFAULT 0;
  DECLARE v_max_rank DOUBLE DEFAULT 0;
  DECLARE v_liq_count INT DEFAULT 0;

  IF p_keep_limit IS NOT NULL AND p_keep_limit > 0 THEN
    SET v_keep_limit = p_keep_limit;
  END IF;

  CREATE TABLE IF NOT EXISTS `jstockdata_reco_quant_score` (
    `generated_at` DATETIME NOT NULL,
    `scrip` VARCHAR(20) NOT NULL,
    `assetclass` VARCHAR(30) NOT NULL,
    `source_rank` INT NULL,
    `quant_score` DECIMAL(10,4) NULL,
    `latest_close_price` DECIMAL(12,2) NULL,
    `liquidity_score` DECIMAL(10,4) NOT NULL,
    `momentum_score` DECIMAL(10,4) NOT NULL,
    `news_score` DECIMAL(10,4) NULL,
    `projection_score` DECIMAL(10,4) NULL,
    `backtest_score` DECIMAL(10,4) NULL,
    `quality_score` DECIMAL(10,4) NULL,
    `quant_analysis_rating` VARCHAR(20) NULL,
    `quant_star_rating` DECIMAL(4,2) NULL,
    `rating_reason` VARCHAR(500) NULL,
    `reco_include_status` VARCHAR(10) NOT NULL,
    `quant_rank` INT NOT NULL,
    `trend_score` DECIMAL(10,4) NOT NULL,
    PRIMARY KEY (`generated_at`, `scrip`),
    KEY `ix_quant_score_status` (`reco_include_status`, `assetclass`, `quant_rank`),
    KEY `ix_quant_score_rating` (`quant_analysis_rating`, `assetclass`, `quant_score`),
    KEY `ix_quant_score_scrip` (`scrip`, `generated_at`)
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

  DROP TEMPORARY TABLE IF EXISTS tmp_projection_component;
  CREATE TEMPORARY TABLE tmp_projection_component AS
  SELECT
    scrip,
    LEAST(100, GREATEST(0,
      50
      + LEAST(18, GREATEST(-18, COALESCE(expected_return_pct, 0) * 4))
      + LEAST(18, GREATEST(-18, (COALESCE(upward_probability_pct, 50) - 50) * 0.6))
      - LEAST(12, GREATEST(0, (COALESCE(downward_probability_pct, 50) - 50) * 0.45))
      + LEAST(10, GREATEST(0, COALESCE(confidence_score, 0) / 10))
      + LEAST(8, GREATEST(-8, COALESCE(risk_reward_ratio, 1) * 2))
    )) AS projection_component
  FROM (
    SELECT p.*,
           @projection_row := IF(@projection_scrip = p.scrip, @projection_row + 1, 1) AS row_no,
           @projection_scrip := p.scrip AS row_scrip
    FROM (
      SELECT p.*
      FROM `jstockdata_reco_projection` p
      JOIN tmp_reco_universe u ON u.scrip = p.scrip
      WHERE p.frequency IN ('DAILY', 'WEEKLY')
      ORDER BY p.scrip, p.generated_at DESC,
               FIELD(p.frequency, 'DAILY', 'WEEKLY'),
               p.confidence_score DESC
    ) p
    CROSS JOIN (SELECT @projection_scrip := '', @projection_row := 0) vars
  ) ranked
  WHERE row_no = 1;
  ALTER TABLE tmp_projection_component ADD PRIMARY KEY (`scrip`);

  DROP TEMPORARY TABLE IF EXISTS tmp_backtest_component;
  CREATE TEMPORARY TABLE tmp_backtest_component AS
  SELECT
    scrip,
    LEAST(100, GREATEST(0,
      50
      + LEAST(20, GREATEST(-20, (COALESCE(backtest_win_rate_pct, 50) - 50) * 0.65))
      + LEAST(18, GREATEST(-18, COALESCE(backtest_avg_trade_return_pct, 0) * 5))
      + LEAST(12, GREATEST(-12, COALESCE(expected_return_pct, 0) * 4))
      - LEAST(18, GREATEST(0, ABS(LEAST(0, COALESCE(backtest_worst_trade_pct, 0))) * 1.25))
      + CASE WHEN COALESCE(backtest_trades, 0) >= 20 THEN 8
             WHEN COALESCE(backtest_trades, 0) >= 10 THEN 4
             ELSE -6 END
    )) AS backtest_component
  FROM (
    SELECT b.*,
           @backtest_row := IF(@backtest_scrip = b.scrip, @backtest_row + 1, 1) AS row_no,
           @backtest_scrip := b.scrip AS row_scrip
    FROM (
      SELECT b.*
      FROM `jstockdata_reco_backtest` b
      JOIN tmp_reco_universe u ON u.scrip = b.scrip
      WHERE b.frequency IN ('DAILY', 'WEEKLY')
      ORDER BY b.scrip, FIELD(b.frequency, 'DAILY', 'WEEKLY'),
               b.projection_confidence_score DESC, b.backtest_trades DESC
    ) b
    CROSS JOIN (SELECT @backtest_scrip := '', @backtest_row := 0) vars
  ) ranked
  WHERE row_no = 1;
  ALTER TABLE tmp_backtest_component ADD PRIMARY KEY (`scrip`);

  DROP TEMPORARY TABLE IF EXISTS tmp_news_component;
  CREATE TEMPORARY TABLE tmp_news_component AS
  SELECT
    scrip,
    LEAST(100, GREATEST(0,
      50
      + LEAST(16, GREATEST(-16, COALESCE(news_sentiment_score, 0) * 0.20))
      + LEAST(12, GREATEST(0, COALESCE(catalyst_score, 0) * 0.20))
      - LEAST(20, GREATEST(0, COALESCE(news_risk_score, 0) * 0.30))
      - CASE WHEN COALESCE(binary_event_risk_flag, 0) = 1 THEN 8 ELSE 0 END
      - CASE WHEN COALESCE(legal_risk_flag, 0) = 1 THEN 10 ELSE 0 END
    )) AS news_component,
    LEAST(30, GREATEST(0, COALESCE(news_risk_score, 0) * 0.30)
      + CASE WHEN COALESCE(binary_event_risk_flag, 0) = 1 THEN 8 ELSE 0 END
      + CASE WHEN COALESCE(legal_risk_flag, 0) = 1 THEN 10 ELSE 0 END
    ) AS news_risk_penalty
  FROM (
    SELECT n.*,
           @news_row := IF(@news_scrip = n.scrip, @news_row + 1, 1) AS row_no,
           @news_scrip := n.scrip AS row_scrip
    FROM (
      SELECT n.*
      FROM `jstockdata_reco_news_signal` n
      JOIN tmp_reco_universe u ON u.scrip = n.scrip
      ORDER BY n.scrip, n.generated_at DESC
    ) n
    CROSS JOIN (SELECT @news_scrip := '', @news_row := 0) vars
  ) ranked
  WHERE row_no = 1;
  ALTER TABLE tmp_news_component ADD PRIMARY KEY (`scrip`);

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
    COALESCE(pc.projection_component, 50) AS projection_component,
    COALESCE(bc.backtest_component, 50) AS backtest_component,
    CASE
      WHEN u.source_rank IS NULL OR v_max_rank = v_min_rank THEN 50
      ELSE 100 - ((u.source_rank - v_min_rank) / NULLIF(v_max_rank - v_min_rank, 0) * 100)
    END AS source_rank_score,
    CASE
      WHEN lr.scrip IS NULL OR v_liq_count <= 1 THEN 50
      ELSE (lr.liq_rank - 1) / NULLIF(v_liq_count - 1, 0) * 100
    END AS liquidity_score,
    COALESCE(nc.news_component, 50) AS news_component,
    COALESCE(nc.news_risk_penalty, 0) AS risk_penalty,
    lr.latest_close_price,
    lr.latest_volume,
    lr.latest_dollar_volume
  FROM tmp_reco_universe u
  LEFT JOIN tmp_universe_trend_score ts ON ts.scrip = u.scrip
  LEFT JOIN tmp_universe_momentum_score ms ON ms.scrip = u.scrip
  LEFT JOIN tmp_universe_liquidity_rank lr ON lr.scrip = u.scrip
  LEFT JOIN tmp_projection_component pc ON pc.scrip = u.scrip
  LEFT JOIN tmp_backtest_component bc ON bc.scrip = u.scrip
  LEFT JOIN tmp_news_component nc ON nc.scrip = u.scrip
  GROUP BY
    u.scrip, u.assetclass, u.source_rank,
    lr.scrip, lr.liq_rank, lr.latest_close_price, lr.latest_volume, lr.latest_dollar_volume,
    pc.projection_component, bc.backtest_component, nc.news_component, nc.news_risk_penalty;
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
        scored.source_rank_score * 0.55
        + scored.liquidity_score * 0.45
      ) AS quality_component,
      LEAST(100, GREATEST(0,
        scored.trend_component * 0.20
        + scored.momentum_component * 0.25
        + scored.projection_component * 0.20
        + scored.backtest_component * 0.15
        + (scored.source_rank_score * 0.55 + scored.liquidity_score * 0.45) * 0.10
        + scored.news_component * 0.10
        - scored.risk_penalty * 0.25
      )) AS universe_score,
      @universe_rank := @universe_rank + 1 AS universe_rank
    FROM (
      SELECT *
      FROM tmp_universe_scored
      ORDER BY
        LEAST(100, GREATEST(0,
          trend_component * 0.20
          + momentum_component * 0.25
          + projection_component * 0.20
          + backtest_component * 0.15
          + (source_rank_score * 0.55 + liquidity_score * 0.45) * 0.10
          + news_component * 0.10
          - risk_penalty * 0.25
        )) DESC,
        projection_component DESC,
        momentum_component DESC,
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

  DELETE FROM `jstockdata_reco_quant_score`
  WHERE generated_at < DATE_SUB(v_generated_at, INTERVAL 180 DAY);

  INSERT INTO `jstockdata_reco_quant_score` (
    generated_at, scrip, assetclass, source_rank, quant_score, latest_close_price,
    liquidity_score, momentum_score, news_score, projection_score, backtest_score,
    quality_score, quant_analysis_rating, quant_star_rating, rating_reason,
    reco_include_status, quant_rank, trend_score
  )
  SELECT
    v_generated_at, scrip, assetclass, source_rank,
    ROUND(universe_score, 4),
    latest_close_price,
    ROUND(liquidity_score, 4),
    ROUND(momentum_component, 4),
    ROUND(news_component, 4),
    ROUND(projection_component, 4),
    ROUND(backtest_component, 4),
    ROUND(quality_component, 4),
    CASE
      WHEN universe_score >= 85 THEN 'STRONG_BUY'
      WHEN universe_score >= 72 THEN 'BUY'
      WHEN universe_score >= 55 THEN 'HOLD'
      WHEN universe_score >= 40 THEN 'SELL'
      ELSE 'STRONG_SELL'
    END,
    ROUND(1 + (universe_score / 100) * 4, 2),
    CONCAT(
      'JSG Quant: trend=', ROUND(trend_component, 1),
      ', momentum=', ROUND(momentum_component, 1),
      ', projection=', ROUND(projection_component, 1),
      ', backtest=', ROUND(backtest_component, 1),
      ', quality=', ROUND(quality_component, 1),
      ', news=', ROUND(news_component, 1)
    ),
    reco_universe_status,
    universe_rank,
    ROUND(trend_component, 4)
  FROM tmp_universe_ranked;

  CALL reco_runlog_mark(
    'reco_universe_status_refresh',
    'SUCCESS',
    CONCAT('Updated JSG Quant score and RecoUniverseStatus for top ', v_keep_limit, ' EQ/ETF scrips at ', v_generated_at)
  );
END$$
DELIMITER ;
