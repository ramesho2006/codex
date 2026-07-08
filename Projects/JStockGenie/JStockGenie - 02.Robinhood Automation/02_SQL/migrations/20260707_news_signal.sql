-- News catalyst overlay for the top recommendation universe.
--
-- External fetch tools populate jstockdata_reco_news_raw.
-- reco_news_signal_refresh() scores recent headlines and creates one current
-- catalyst row per active KEEP / rank <= 1000 scrip.

CREATE TABLE IF NOT EXISTS `jstockdata_reco_news_raw` (
  `news_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `provider` VARCHAR(30) NOT NULL,
  `scrip` VARCHAR(20) NOT NULL,
  `published_at` DATETIME NULL,
  `source_name` VARCHAR(120) NULL,
  `headline` VARCHAR(500) NOT NULL,
  `summary` TEXT NULL,
  `url` VARCHAR(1000) NULL,
  `provider_sentiment` VARCHAR(30) NULL,
  `provider_score` DECIMAL(10,4) NULL,
  `fetched_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`news_id`),
  UNIQUE KEY `ux_reco_news_provider_url_scrip` (`provider`, `scrip`, `url`(255)),
  KEY `ix_reco_news_scrip_published` (`scrip`, `published_at`),
  KEY `ix_reco_news_provider_fetched` (`provider`, `fetched_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `jstockdata_reco_news_signal` (
  `scrip` VARCHAR(20) NOT NULL,
  `generated_at` DATETIME NOT NULL,
  `lookback_days` INT NOT NULL,
  `news_count` INT NOT NULL,
  `latest_news_at` DATETIME NULL,
  `bullish_news_count` INT NOT NULL,
  `bearish_news_count` INT NOT NULL,
  `neutral_news_count` INT NOT NULL,
  `news_sentiment_score` DECIMAL(10,2) NOT NULL,
  `news_recency_score` DECIMAL(10,2) NOT NULL,
  `catalyst_score` DECIMAL(10,2) NOT NULL,
  `news_risk_score` DECIMAL(10,2) NOT NULL,
  `binary_event_risk_flag` TINYINT(1) NOT NULL,
  `earnings_risk_flag` TINYINT(1) NOT NULL,
  `legal_risk_flag` TINYINT(1) NOT NULL,
  `analyst_upgrade_flag` TINYINT(1) NOT NULL,
  `analyst_downgrade_flag` TINYINT(1) NOT NULL,
  `swing_news_signal` VARCHAR(20) NOT NULL,
  `options_news_signal` VARCHAR(30) NOT NULL,
  `top_headline` VARCHAR(500) NULL,
  `top_url` VARCHAR(1000) NULL,
  PRIMARY KEY (`scrip`),
  KEY `ix_reco_news_signal_swing` (`swing_news_signal`, `news_sentiment_score`),
  KEY `ix_reco_news_signal_options` (`options_news_signal`, `news_risk_score`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET @column_exists := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'jstockdata_reco_weekly_target_recos'
    AND COLUMN_NAME = 'news_swing_signal'
);
SET @ddl := IF(@column_exists = 0,
  'ALTER TABLE jstockdata_reco_weekly_target_recos ADD COLUMN news_swing_signal VARCHAR(20) NULL',
  'SELECT ''news_swing_signal already exists'' AS migration_note');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @column_exists := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'jstockdata_reco_weekly_target_recos'
    AND COLUMN_NAME = 'news_options_signal'
);
SET @ddl := IF(@column_exists = 0,
  'ALTER TABLE jstockdata_reco_weekly_target_recos ADD COLUMN news_options_signal VARCHAR(30) NULL',
  'SELECT ''news_options_signal already exists'' AS migration_note');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @column_exists := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'jstockdata_reco_weekly_target_recos'
    AND COLUMN_NAME = 'news_sentiment_score'
);
SET @ddl := IF(@column_exists = 0,
  'ALTER TABLE jstockdata_reco_weekly_target_recos ADD COLUMN news_sentiment_score DECIMAL(10,2) NULL',
  'SELECT ''news_sentiment_score already exists'' AS migration_note');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @column_exists := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'jstockdata_reco_weekly_target_recos'
    AND COLUMN_NAME = 'news_catalyst_score'
);
SET @ddl := IF(@column_exists = 0,
  'ALTER TABLE jstockdata_reco_weekly_target_recos ADD COLUMN news_catalyst_score DECIMAL(10,2) NULL',
  'SELECT ''news_catalyst_score already exists'' AS migration_note');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @column_exists := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'jstockdata_reco_weekly_target_recos'
    AND COLUMN_NAME = 'news_risk_score'
);
SET @ddl := IF(@column_exists = 0,
  'ALTER TABLE jstockdata_reco_weekly_target_recos ADD COLUMN news_risk_score DECIMAL(10,2) NULL',
  'SELECT ''news_risk_score already exists'' AS migration_note');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @column_exists := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'jstockdata_reco_weekly_target_recos'
    AND COLUMN_NAME = 'news_top_headline'
);
SET @ddl := IF(@column_exists = 0,
  'ALTER TABLE jstockdata_reco_weekly_target_recos ADD COLUMN news_top_headline VARCHAR(500) NULL',
  'SELECT ''news_top_headline already exists'' AS migration_note');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @column_exists := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'jstockdata_reco_weekly_target_recos'
    AND COLUMN_NAME = 'news_top_url'
);
SET @ddl := IF(@column_exists = 0,
  'ALTER TABLE jstockdata_reco_weekly_target_recos ADD COLUMN news_top_url VARCHAR(1000) NULL',
  'SELECT ''news_top_url already exists'' AS migration_note');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS `reco_news_signal_refresh`;

DELIMITER $$
CREATE PROCEDURE `reco_news_signal_refresh`(IN p_lookback_days INT)
BEGIN
  DECLARE v_generated_at DATETIME DEFAULT NOW();
  DECLARE v_lookback_days INT DEFAULT 7;

  IF p_lookback_days IS NOT NULL AND p_lookback_days > 0 THEN
    SET v_lookback_days = p_lookback_days;
  END IF;

  DROP TEMPORARY TABLE IF EXISTS tmp_news_universe;
  CREATE TEMPORARY TABLE tmp_news_universe AS
  SELECT
    s.`Scrip` AS scrip,
    s.`AssetClass` AS assetclass,
    s.`RecoUniverseRank` AS reco_universe_rank
  FROM `jstockdata_scrips` s
  WHERE UPPER(TRIM(COALESCE(s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
    AND COALESCE(s.`RecoUniverseRank`, 999999) <= 1000
    AND UPPER(TRIM(s.`AssetClass`)) IN ('EQ', 'ETF');
  ALTER TABLE tmp_news_universe ADD PRIMARY KEY (`scrip`);

  DROP TEMPORARY TABLE IF EXISTS tmp_news_recent;
  CREATE TEMPORARY TABLE tmp_news_recent AS
  SELECT
    n.news_id,
    n.scrip,
    n.published_at,
    n.headline,
    n.summary,
    n.url,
    LOWER(CONCAT(COALESCE(n.headline, ''), ' ', COALESCE(n.summary, ''))) AS news_text,
    GREATEST(0, DATEDIFF(v_generated_at, COALESCE(n.published_at, n.fetched_at))) AS news_age_days
  FROM `jstockdata_reco_news_raw` n
  JOIN tmp_news_universe u ON u.scrip = n.scrip
  WHERE COALESCE(n.published_at, n.fetched_at) >= DATE_SUB(v_generated_at, INTERVAL v_lookback_days DAY);
  ALTER TABLE tmp_news_recent ADD KEY `ix_tmp_news_recent_scrip` (`scrip`, `published_at`);

  DROP TEMPORARY TABLE IF EXISTS tmp_news_classified;
  CREATE TEMPORARY TABLE tmp_news_classified AS
  SELECT
    r.*,
    (
      CASE WHEN news_text LIKE '%upgrade%' OR news_text LIKE '%raises price target%' OR news_text LIKE '%price target raised%' THEN 18 ELSE 0 END
      + CASE WHEN news_text LIKE '%beats estimates%' OR news_text LIKE '%beats expectations%' OR news_text LIKE '%beat earnings%' THEN 16 ELSE 0 END
      + CASE WHEN news_text LIKE '%raises guidance%' OR news_text LIKE '%strong guidance%' OR news_text LIKE '%record revenue%' THEN 16 ELSE 0 END
      + CASE WHEN news_text LIKE '%partnership%' OR news_text LIKE '%contract%' OR news_text LIKE '%approval%' OR news_text LIKE '%buyback%' THEN 10 ELSE 0 END
      + CASE WHEN news_text LIKE '%dividend increase%' OR news_text LIKE '%increases dividend%' THEN 8 ELSE 0 END
      - CASE WHEN news_text LIKE '%downgrade%' OR news_text LIKE '%cuts price target%' OR news_text LIKE '%price target cut%' THEN 18 ELSE 0 END
      - CASE WHEN news_text LIKE '%misses estimates%' OR news_text LIKE '%missed expectations%' OR news_text LIKE '%weak guidance%' THEN 18 ELSE 0 END
      - CASE WHEN news_text LIKE '%lawsuit%' OR news_text LIKE '%investigation%' OR news_text LIKE '%probe%' OR news_text LIKE '%sec charges%' THEN 20 ELSE 0 END
      - CASE WHEN news_text LIKE '%recall%' OR news_text LIKE '%bankruptcy%' OR news_text LIKE '%fraud%' OR news_text LIKE '%data breach%' THEN 22 ELSE 0 END
      - CASE WHEN news_text LIKE '%offering%' OR news_text LIKE '%share dilution%' OR news_text LIKE '%secondary offering%' THEN 14 ELSE 0 END
    ) AS headline_sentiment_points,
    (
      CASE WHEN news_text LIKE '%earnings%' OR news_text LIKE '%results%' OR news_text LIKE '%guidance%' THEN 14 ELSE 0 END
      + CASE WHEN news_text LIKE '%fda%' OR news_text LIKE '%approval%' OR news_text LIKE '%clinical trial%' OR news_text LIKE '%phase 3%' THEN 18 ELSE 0 END
      + CASE WHEN news_text LIKE '%merger%' OR news_text LIKE '%acquisition%' OR news_text LIKE '%takeover%' THEN 18 ELSE 0 END
      + CASE WHEN news_text LIKE '%upgrade%' OR news_text LIKE '%downgrade%' OR news_text LIKE '%price target%' THEN 10 ELSE 0 END
      + CASE WHEN news_text LIKE '%lawsuit%' OR news_text LIKE '%investigation%' OR news_text LIKE '%probe%' OR news_text LIKE '%recall%' THEN 16 ELSE 0 END
    ) AS catalyst_points,
    (
      CASE WHEN news_text LIKE '%earnings%' OR news_text LIKE '%guidance%' THEN 16 ELSE 0 END
      + CASE WHEN news_text LIKE '%fda%' OR news_text LIKE '%clinical trial%' OR news_text LIKE '%phase 3%' THEN 22 ELSE 0 END
      + CASE WHEN news_text LIKE '%lawsuit%' OR news_text LIKE '%investigation%' OR news_text LIKE '%probe%' OR news_text LIKE '%fraud%' THEN 26 ELSE 0 END
      + CASE WHEN news_text LIKE '%downgrade%' OR news_text LIKE '%weak guidance%' OR news_text LIKE '%misses estimates%' THEN 16 ELSE 0 END
      + CASE WHEN news_text LIKE '%merger%' OR news_text LIKE '%acquisition%' OR news_text LIKE '%takeover%' THEN 14 ELSE 0 END
    ) AS risk_points,
    CASE WHEN news_text LIKE '%earnings%' OR news_text LIKE '%guidance%' THEN 1 ELSE 0 END AS earnings_flag,
    CASE WHEN news_text LIKE '%lawsuit%' OR news_text LIKE '%investigation%' OR news_text LIKE '%probe%' OR news_text LIKE '%fraud%' THEN 1 ELSE 0 END AS legal_flag,
    CASE WHEN news_text LIKE '%fda%' OR news_text LIKE '%clinical trial%' OR news_text LIKE '%phase 3%' OR news_text LIKE '%merger%' OR news_text LIKE '%acquisition%' OR news_text LIKE '%takeover%' THEN 1 ELSE 0 END AS binary_flag,
    CASE WHEN news_text LIKE '%upgrade%' OR news_text LIKE '%raises price target%' OR news_text LIKE '%price target raised%' THEN 1 ELSE 0 END AS upgrade_flag,
    CASE WHEN news_text LIKE '%downgrade%' OR news_text LIKE '%cuts price target%' OR news_text LIKE '%price target cut%' THEN 1 ELSE 0 END AS downgrade_flag,
    CASE
      WHEN news_age_days <= 1 THEN 1.00
      WHEN news_age_days <= 3 THEN 0.70
      WHEN news_age_days <= 7 THEN 0.40
      ELSE 0.20
    END AS recency_weight
  FROM tmp_news_recent r;
  ALTER TABLE tmp_news_classified ADD KEY `ix_tmp_news_classified_scrip` (`scrip`);

  DROP TEMPORARY TABLE IF EXISTS tmp_news_agg;
  CREATE TEMPORARY TABLE tmp_news_agg AS
  SELECT
    c.scrip,
    COUNT(*) AS news_count,
    MAX(c.published_at) AS latest_news_at,
    SUM(c.headline_sentiment_points > 5) AS bullish_news_count,
    SUM(c.headline_sentiment_points < -5) AS bearish_news_count,
    SUM(c.headline_sentiment_points BETWEEN -5 AND 5) AS neutral_news_count,
    ROUND(SUM(c.headline_sentiment_points * c.recency_weight), 2) AS news_sentiment_score,
    ROUND(SUM(25 * c.recency_weight), 2) AS news_recency_score,
    ROUND(SUM(c.catalyst_points * c.recency_weight), 2) AS catalyst_score,
    ROUND(SUM(c.risk_points * c.recency_weight), 2) AS news_risk_score,
    MAX(c.binary_flag) AS binary_event_risk_flag,
    MAX(c.earnings_flag) AS earnings_risk_flag,
    MAX(c.legal_flag) AS legal_risk_flag,
    MAX(c.upgrade_flag) AS analyst_upgrade_flag,
    MAX(c.downgrade_flag) AS analyst_downgrade_flag
  FROM tmp_news_classified c
  GROUP BY c.scrip;
  ALTER TABLE tmp_news_agg ADD PRIMARY KEY (`scrip`);

  DROP TEMPORARY TABLE IF EXISTS tmp_news_top;
  CREATE TEMPORARY TABLE tmp_news_top AS
  SELECT ranked.scrip, ranked.headline, ranked.url
  FROM (
    SELECT
      c.*,
      @row_num := IF(@row_key = c.scrip, @row_num + 1, 1) AS row_num,
      @row_key := c.scrip AS row_key_set
    FROM (
      SELECT *
      FROM tmp_news_classified
      ORDER BY scrip, (ABS(headline_sentiment_points) + catalyst_points + risk_points) DESC, published_at DESC, news_id DESC
    ) c
    CROSS JOIN (SELECT @row_key := '', @row_num := 0) vars
  ) ranked
  WHERE ranked.row_num = 1;
  ALTER TABLE tmp_news_top ADD PRIMARY KEY (`scrip`);

  TRUNCATE TABLE `jstockdata_reco_news_signal`;

  INSERT INTO `jstockdata_reco_news_signal` (
    scrip, generated_at, lookback_days, news_count, latest_news_at,
    bullish_news_count, bearish_news_count, neutral_news_count,
    news_sentiment_score, news_recency_score, catalyst_score, news_risk_score,
    binary_event_risk_flag, earnings_risk_flag, legal_risk_flag,
    analyst_upgrade_flag, analyst_downgrade_flag,
    swing_news_signal, options_news_signal, top_headline, top_url
  )
  SELECT
    u.scrip,
    v_generated_at,
    v_lookback_days,
    COALESCE(a.news_count, 0),
    a.latest_news_at,
    COALESCE(a.bullish_news_count, 0),
    COALESCE(a.bearish_news_count, 0),
    COALESCE(a.neutral_news_count, 0),
    COALESCE(a.news_sentiment_score, 0),
    COALESCE(a.news_recency_score, 0),
    COALESCE(a.catalyst_score, 0),
    COALESCE(a.news_risk_score, 0),
    COALESCE(a.binary_event_risk_flag, 0),
    COALESCE(a.earnings_risk_flag, 0),
    COALESCE(a.legal_risk_flag, 0),
    COALESCE(a.analyst_upgrade_flag, 0),
    COALESCE(a.analyst_downgrade_flag, 0),
    CASE
      WHEN COALESCE(a.news_count, 0) = 0 THEN 'NO_RECENT_NEWS'
      WHEN COALESCE(a.news_risk_score, 0) >= 45 OR COALESCE(a.legal_risk_flag, 0) = 1 THEN 'NEWS_RISK_AVOID'
      WHEN COALESCE(a.news_sentiment_score, 0) >= 20 AND COALESCE(a.catalyst_score, 0) >= 15 THEN 'BULLISH_CATALYST'
      WHEN COALESCE(a.news_sentiment_score, 0) <= -20 THEN 'BEARISH_CATALYST'
      ELSE 'NEWS_NEUTRAL'
    END AS swing_news_signal,
    CASE
      WHEN COALESCE(a.news_count, 0) = 0 THEN 'NO_RECENT_NEWS'
      WHEN COALESCE(a.binary_event_risk_flag, 0) = 1 OR COALESCE(a.earnings_risk_flag, 0) = 1 THEN 'AVOID_SHORT_PREMIUM_EVENT'
      WHEN COALESCE(a.news_risk_score, 0) >= 45 OR COALESCE(a.legal_risk_flag, 0) = 1 THEN 'AVOID_OPTIONS_NEWS_RISK'
      WHEN COALESCE(a.news_sentiment_score, 0) >= 20 THEN 'SUPPORTS_SELL_PUT'
      WHEN COALESCE(a.news_sentiment_score, 0) <= -20 THEN 'SUPPORTS_SELL_CALL'
      ELSE 'OPTIONS_NEUTRAL'
    END AS options_news_signal,
    t.headline,
    t.url
  FROM tmp_news_universe u
  LEFT JOIN tmp_news_agg a ON a.scrip = u.scrip
  LEFT JOIN tmp_news_top t ON t.scrip = u.scrip;

  CALL reco_runlog_mark(
    'reco_news_signal_refresh',
    'SUCCESS',
    CONCAT('Generated news catalyst signals for top universe; lookback_days=', v_lookback_days, '; generated_at=', v_generated_at)
  );
END$$
DELIMITER ;
