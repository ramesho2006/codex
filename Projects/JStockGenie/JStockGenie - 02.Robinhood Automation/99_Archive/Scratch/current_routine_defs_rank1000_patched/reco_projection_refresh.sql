CREATE DEFINER=`admin`@`%` PROCEDURE `reco_projection_refresh`()
BEGIN
  DECLARE v_generated_at DATETIME DEFAULT NOW();
  CREATE TABLE IF NOT EXISTS `jstockdata_reco_projection` (
    `projection_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `generated_at` DATETIME NOT NULL,
    `scrip` VARCHAR(20) NOT NULL,
    `frequency` VARCHAR(20) NOT NULL,
    `assetclass` VARCHAR(30) NULL,
    `signal_direction` VARCHAR(10) NOT NULL,
    `signal_context_key` VARCHAR(160) NOT NULL,
    `horizon_bars` INT NOT NULL,
    `horizon_days` INT NOT NULL,
    `horizon_weeks` DECIMAL(8,2) NOT NULL,
    `sample_size` INT NOT NULL,
    `upward_projection_pct` DECIMAL(10,2) NULL,
    `upward_probability_pct` DECIMAL(6,2) NULL,
    `downward_projection_pct` DECIMAL(10,2) NULL,
    `downward_probability_pct` DECIMAL(6,2) NULL,
    `expected_return_pct` DECIMAL(10,2) NULL,
    `risk_reward_ratio` DECIMAL(10,2) NULL,
    `confidence_score` DECIMAL(6,2) NULL,
    PRIMARY KEY (`projection_id`),
    KEY `ix_reco_projection_lookup` (`scrip`, `frequency`, `signal_direction`, `horizon_bars`),
    KEY `ix_reco_projection_context` (`frequency`, `signal_direction`, `signal_context_key`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  TRUNCATE TABLE `jstockdata_reco_projection`;
  DROP TABLE IF EXISTS `jstockdata_reco_projection_work_base`;
  CREATE TABLE `jstockdata_reco_projection_work_base` AS
  SELECT ordered.*, @row_num := IF(@row_key = CONCAT(ordered.scrip, '|', ordered.frequency), @row_num + 1, 1) AS seq_num,
         @row_key := CONCAT(ordered.scrip, '|', ordered.frequency) AS seq_key
  FROM (
    SELECT e.`SCRIP` AS scrip, TRIM(REPLACE(e.`FREQUENCY`, '\r', '')) AS frequency, e.`DATE` AS signal_date,
           e.`Close` AS close_price, COALESCE(s.`AssetClass`, 'UNKNOWN') AS assetclass,
           UPPER(TRIM(COALESCE(e.`Combined_Signal`, ''))) AS signal_direction,
           CONCAT('CS=', UPPER(TRIM(COALESCE(e.`Combined_Signal`, ''))),
                  '|CSI=', UPPER(TRIM(COALESCE(e.`Combined_Signal_Ind`, ''))),
                  '|SMA=', UPPER(TRIM(COALESCE(e.`SMADeltaTrend`, ''))),
                  '|LO=', UPPER(TRIM(COALESCE(e.`LODeltaSignal`, '')))) AS signal_context_key
    FROM `jstockdata_hatrend_extend` e
    JOIN `jstockdata_scrips` s
      ON s.`Scrip` = e.`SCRIP`
     AND UPPER(TRIM(COALESCE(s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(s.`RecoUniverseRank`, 999999) <= 1000
    WHERE TRIM(REPLACE(e.`FREQUENCY`, '\r', '')) IN ('DAILY', 'WEEKLY') AND e.`Close` > 0
    ORDER BY e.`SCRIP`, TRIM(REPLACE(e.`FREQUENCY`, '\r', '')), e.`DATE`
  ) ordered CROSS JOIN (SELECT @row_key := '', @row_num := 0) vars;
  ALTER TABLE `jstockdata_reco_projection_work_base` ADD PRIMARY KEY (`scrip`, `frequency`, `seq_num`), ADD KEY `ix_projection_event` (`scrip`, `frequency`, `signal_direction`, `signal_date`);
  DROP TEMPORARY TABLE IF EXISTS tmp_reco_projection_horizons;
  CREATE TEMPORARY TABLE tmp_reco_projection_horizons (horizon_bars INT NOT NULL, horizon_days INT NOT NULL, horizon_weeks DECIMAL(8,2) NOT NULL, PRIMARY KEY (horizon_bars));
  INSERT INTO tmp_reco_projection_horizons VALUES (5, 5, 1.00), (10, 10, 2.00), (20, 20, 4.00);
  DROP TEMPORARY TABLE IF EXISTS tmp_reco_projection_returns;
  CREATE TEMPORARY TABLE tmp_reco_projection_returns AS
  SELECT b.scrip, b.frequency, b.assetclass, b.signal_direction, b.signal_context_key,
         h.horizon_bars,
         CASE WHEN b.frequency = 'WEEKLY' THEN h.horizon_bars * 5 ELSE h.horizon_days END AS horizon_days_effective,
         CASE WHEN b.frequency = 'WEEKLY' THEN h.horizon_bars ELSE h.horizon_weeks END AS horizon_weeks_effective,
         CASE WHEN b.signal_direction = 'SELL' THEN ROUND((b.close_price - f.close_price) / b.close_price * 100, 4)
              ELSE ROUND((f.close_price - b.close_price) / b.close_price * 100, 4) END AS return_pct
  FROM `jstockdata_reco_projection_work_base` b
  JOIN tmp_reco_projection_horizons h
  JOIN `jstockdata_reco_projection_work_base` f ON f.scrip = b.scrip AND f.frequency = b.frequency AND f.seq_num = b.seq_num + h.horizon_bars
  WHERE b.signal_direction IN ('BUY', 'SELL') AND b.close_price > 0 AND f.close_price > 0;
  ALTER TABLE tmp_reco_projection_returns ADD KEY `ix_projection_returns_group` (`scrip`, `frequency`, `signal_direction`, `signal_context_key`, `horizon_bars`);
  INSERT INTO `jstockdata_reco_projection` (generated_at, scrip, frequency, assetclass, signal_direction, signal_context_key, horizon_bars, horizon_days, horizon_weeks, sample_size, upward_projection_pct, upward_probability_pct, downward_projection_pct, downward_probability_pct, expected_return_pct, risk_reward_ratio, confidence_score)
  SELECT v_generated_at, r.scrip, r.frequency, MAX(r.assetclass), r.signal_direction, r.signal_context_key, r.horizon_bars,
         MAX(r.horizon_days_effective), MAX(r.horizon_weeks_effective), COUNT(*),
         ROUND(AVG(CASE WHEN r.return_pct > 0 THEN r.return_pct END), 2),
         ROUND(SUM(CASE WHEN r.return_pct > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2),
         ROUND(ABS(AVG(CASE WHEN r.return_pct < 0 THEN r.return_pct END)), 2),
         ROUND(SUM(CASE WHEN r.return_pct < 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2),
         ROUND(AVG(r.return_pct), 2),
         ROUND(COALESCE(AVG(CASE WHEN r.return_pct > 0 THEN r.return_pct END), 0) / NULLIF(ABS(COALESCE(AVG(CASE WHEN r.return_pct < 0 THEN r.return_pct END), 0)), 0), 2),
         ROUND(LEAST(100, COUNT(*) * 4 + ABS(AVG(r.return_pct)) * 5), 2)
  FROM tmp_reco_projection_returns r
  GROUP BY r.scrip, r.frequency, r.signal_direction, r.signal_context_key, r.horizon_bars
  HAVING COUNT(*) >= 3;
  DROP TABLE IF EXISTS `jstockdata_reco_projection_work_base`;
  CALL reco_runlog_mark('reco_projection_refresh', 'SUCCESS', CONCAT('Generated projection rows at ', v_generated_at));
END