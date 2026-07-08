-- Apply jstockdata_scrips.RecoUniverseStatus = 'KEEP' and RecoUniverseRank <= 1000 to recommendation refresh routines.
-- Run after 20260706_add_reco_universe_status_to_scrips.sql and 20260707_universe_status_refresh.sql.


DROP PROCEDURE IF EXISTS `reco_backtest`;
DELIMITER $$
CREATE DEFINER=`admin`@`%` PROCEDURE `reco_backtest`()
BEGIN
    SET @min_trades := 3;
    DROP TEMPORARY TABLE IF EXISTS tmp_reco_hatrend_base;
    CREATE TEMPORARY TABLE tmp_reco_hatrend_base AS
    SELECT
        h.`SCRIP` AS scrip,
        TRIM(REPLACE(h.`Frequency`, '\r', '')) AS frequency,
        h.`DATE` AS trade_date,
        h.`CLOSE` AS close_price,
        UPPER(TRIM(COALESCE(h.`HATrendSignal`, ''))) AS ha_signal,
        UPPER(TRIM(COALESCE(h.`HATrendCorrect`, ''))) AS ha_trend
    FROM `jstockdata_hatrend` h
    JOIN `jstockdata_scrips` universe_s
      ON universe_s.`Scrip` = h.`SCRIP`
     AND UPPER(TRIM(COALESCE(universe_s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(universe_s.`RecoUniverseRank`, 999999) <= 1000
    WHERE TRIM(REPLACE(h.`Frequency`, '\r', '')) IN ('DAILY', 'WEEKLY')
      AND h.`CLOSE` > 0;

    ALTER TABLE tmp_reco_hatrend_base
        ADD PRIMARY KEY (scrip, frequency, trade_date);

    DROP TEMPORARY TABLE IF EXISTS tmp_reco_extend_base;
    CREATE TEMPORARY TABLE tmp_reco_extend_base AS
    SELECT
        e.`SCRIP` AS scrip,
        TRIM(REPLACE(e.`FREQUENCY`, '\r', '')) AS frequency,
        e.`DATE` AS trade_date,
        UPPER(TRIM(COALESCE(e.`SMADeltaTrend`, ''))) AS sma_delta_trend,
        UPPER(TRIM(COALESCE(e.`Combined_Signal`, ''))) AS combined_signal
    FROM `jstockdata_hatrend_extend` e
    JOIN `jstockdata_scrips` universe_s
      ON universe_s.`Scrip` = e.`SCRIP`
     AND UPPER(TRIM(COALESCE(universe_s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(universe_s.`RecoUniverseRank`, 999999) <= 1000
    WHERE TRIM(REPLACE(e.`FREQUENCY`, '\r', '')) IN ('DAILY', 'WEEKLY')
      AND UPPER(TRIM(COALESCE(e.`Combined_Signal`, ''))) IN ('BUY', 'SELL');

    ALTER TABLE tmp_reco_extend_base
        ADD PRIMARY KEY (scrip, frequency, trade_date);

    DROP TEMPORARY TABLE IF EXISTS tmp_reco_signal_source;
    CREATE TEMPORARY TABLE tmp_reco_signal_source AS
    SELECT
        h.scrip,
        h.frequency,
        h.trade_date,
        h.close_price,
        h.ha_signal,
        h.ha_trend,
        e.sma_delta_trend,
        e.combined_signal
    FROM tmp_reco_hatrend_base h
    JOIN tmp_reco_extend_base e
      ON e.scrip = h.scrip
     AND e.frequency = h.frequency
     AND e.trade_date = h.trade_date;

    ALTER TABLE tmp_reco_signal_source
        ADD INDEX ix_source (scrip, frequency, trade_date);

    DROP TEMPORARY TABLE IF EXISTS tmp_reco_signal_ordered;
    CREATE TEMPORARY TABLE tmp_reco_signal_ordered AS
    SELECT
        scrip,
        frequency,
        trade_date,
        close_price,
        ha_signal,
        ha_trend,
        sma_delta_trend,
        combined_signal,
        signal_changed,
        event_seq
    FROM (
        SELECT
            ordered.*,
            @signal_changed := IF(
                @signal_key <> CONCAT(ordered.scrip, '|', ordered.frequency)
                OR @previous_signal <> ordered.combined_signal,
                1,
                0
            ) AS signal_changed,
            @event_seq := IF(
                @signal_key <> CONCAT(ordered.scrip, '|', ordered.frequency),
                1,
                @event_seq + 1
            ) AS event_seq,
            @previous_signal := ordered.combined_signal AS previous_signal_set,
            @signal_key := CONCAT(ordered.scrip, '|', ordered.frequency) AS signal_key_set
        FROM (
            SELECT *
            FROM tmp_reco_signal_source
            ORDER BY scrip, frequency, trade_date
        ) ordered
        CROSS JOIN (
            SELECT @signal_key := '', @previous_signal := '',
                   @signal_changed := 0, @event_seq := 0
        ) vars
    ) numbered;

    ALTER TABLE tmp_reco_signal_ordered
        ADD INDEX ix_ordered (scrip, frequency, event_seq, signal_changed);

    DROP TEMPORARY TABLE IF EXISTS tmp_reco_events_raw;
    CREATE TEMPORARY TABLE tmp_reco_events_raw AS
    SELECT
        scrip,
        frequency,
        trade_date,
        close_price,
        combined_signal AS trade_signal
    FROM tmp_reco_signal_ordered
    WHERE signal_changed = 1;

    ALTER TABLE tmp_reco_events_raw
        ADD INDEX ix_events_raw (scrip, frequency, trade_date);

    DROP TEMPORARY TABLE IF EXISTS tmp_reco_events;
    CREATE TEMPORARY TABLE tmp_reco_events AS
    SELECT
        scrip,
        frequency,
        trade_date,
        close_price,
        trade_signal,
        change_seq AS event_seq
    FROM (
        SELECT
            raw_events.*,
            @change_seq := IF(
                @change_key = CONCAT(raw_events.scrip, '|', raw_events.frequency),
                @change_seq + 1,
                1
            ) AS change_seq,
            @change_key := CONCAT(raw_events.scrip, '|', raw_events.frequency)
                AS change_key_set
        FROM (
            SELECT *
            FROM tmp_reco_events_raw
            ORDER BY scrip, frequency, trade_date
        ) raw_events
        CROSS JOIN (SELECT @change_key := '', @change_seq := 0) vars
    ) sequenced;

    ALTER TABLE tmp_reco_events
        ADD INDEX ix_events (scrip, frequency, event_seq);

    DROP TEMPORARY TABLE IF EXISTS tmp_reco_events_sell;
    CREATE TEMPORARY TABLE tmp_reco_events_sell AS
    SELECT * FROM tmp_reco_events;
    ALTER TABLE tmp_reco_events_sell
        ADD INDEX ix_events_sell (scrip, frequency, event_seq);

    DROP TEMPORARY TABLE IF EXISTS tmp_reco_trades;
    CREATE TEMPORARY TABLE tmp_reco_trades AS
    SELECT
        buy_event.scrip,
        buy_event.frequency,
        buy_event.trade_date AS entry_date,
        sell_event.trade_date AS exit_date,
        buy_event.close_price AS entry_price,
        sell_event.close_price AS exit_price,
        sell_event.close_price / buy_event.close_price AS return_ratio,
        ((sell_event.close_price / buy_event.close_price) - 1) * 100 AS return_pct
    FROM tmp_reco_events buy_event
    JOIN tmp_reco_events_sell sell_event
      ON sell_event.scrip = buy_event.scrip
     AND sell_event.frequency = buy_event.frequency
     AND sell_event.event_seq = buy_event.event_seq + 1
    WHERE buy_event.trade_signal = 'BUY'
      AND sell_event.trade_signal = 'SELL';

    ALTER TABLE tmp_reco_trades
        ADD INDEX ix_trades (scrip, frequency);

    DROP TEMPORARY TABLE IF EXISTS tmp_reco_metrics;
    CREATE TEMPORARY TABLE tmp_reco_metrics AS
    SELECT
        t.scrip,
        t.frequency,
        COUNT(*) AS backtest_trades,
        SUM(t.return_pct > 0) * 100.0 / COUNT(*) AS backtest_win_rate_pct,
        (EXP(SUM(LN(t.return_ratio))) - 1) * 100 AS backtest_total_return_pct,
        AVG(t.return_pct) AS backtest_avg_trade_return_pct,
        MIN(t.return_pct) AS backtest_worst_trade_pct
    FROM tmp_reco_trades t
    GROUP BY t.scrip, t.frequency
    HAVING COUNT(*) >= @min_trades;

    ALTER TABLE tmp_reco_metrics
        ADD PRIMARY KEY (scrip, frequency);

    SET @metric_count := (SELECT COUNT(*) FROM tmp_reco_metrics);

    DROP TEMPORARY TABLE IF EXISTS tmp_reco_rank_total;
    CREATE TEMPORARY TABLE tmp_reco_rank_total AS
    SELECT scrip, frequency, @rn_total := @rn_total + 1 AS metric_rank
    FROM (
        SELECT scrip, frequency
        FROM tmp_reco_metrics
        ORDER BY backtest_total_return_pct, scrip, frequency
    ) ordered
    CROSS JOIN (SELECT @rn_total := 0) vars;
    ALTER TABLE tmp_reco_rank_total ADD PRIMARY KEY (scrip, frequency);

    DROP TEMPORARY TABLE IF EXISTS tmp_reco_rank_win;
    CREATE TEMPORARY TABLE tmp_reco_rank_win AS
    SELECT scrip, frequency, @rn_win := @rn_win + 1 AS metric_rank
    FROM (
        SELECT scrip, frequency
        FROM tmp_reco_metrics
        ORDER BY backtest_win_rate_pct, scrip, frequency
    ) ordered
    CROSS JOIN (SELECT @rn_win := 0) vars;
    ALTER TABLE tmp_reco_rank_win ADD PRIMARY KEY (scrip, frequency);

    DROP TEMPORARY TABLE IF EXISTS tmp_reco_rank_avg;
    CREATE TEMPORARY TABLE tmp_reco_rank_avg AS
    SELECT scrip, frequency, @rn_avg := @rn_avg + 1 AS metric_rank
    FROM (
        SELECT scrip, frequency
        FROM tmp_reco_metrics
        ORDER BY backtest_avg_trade_return_pct, scrip, frequency
    ) ordered
    CROSS JOIN (SELECT @rn_avg := 0) vars;
    ALTER TABLE tmp_reco_rank_avg ADD PRIMARY KEY (scrip, frequency);

    DROP TEMPORARY TABLE IF EXISTS tmp_reco_rank_drawdown;
    CREATE TEMPORARY TABLE tmp_reco_rank_drawdown AS
    SELECT scrip, frequency, @rn_drawdown := @rn_drawdown + 1 AS metric_rank
    FROM (
        SELECT scrip, frequency
        FROM tmp_reco_metrics
        ORDER BY ABS(backtest_worst_trade_pct), scrip, frequency
    ) ordered
    CROSS JOIN (SELECT @rn_drawdown := 0) vars;
    ALTER TABLE tmp_reco_rank_drawdown ADD PRIMARY KEY (scrip, frequency);

    DROP TEMPORARY TABLE IF EXISTS tmp_reco_latest_context;
    CREATE TEMPORARY TABLE tmp_reco_latest_context AS
    SELECT
        ranked.scrip,
        ranked.frequency,
        ranked.trade_date AS latest_date,
        ranked.close_price,
        ranked.ha_signal,
        ranked.ha_trend,
        ranked.sma_delta_trend,
        ranked.combined_signal AS trade_signal
    FROM (
        SELECT
            ordered.*,
            @latest_row := IF(
                @latest_key = CONCAT(ordered.scrip, '|', ordered.frequency),
                @latest_row + 1,
                1
            ) AS latest_row,
            @latest_key := CONCAT(ordered.scrip, '|', ordered.frequency)
                AS latest_key_set
        FROM (
            SELECT *
            FROM tmp_reco_signal_source
            ORDER BY scrip, frequency, trade_date DESC
        ) ordered
        CROSS JOIN (SELECT @latest_key := '', @latest_row := 0) vars
    ) ranked
    WHERE ranked.latest_row = 1;
    ALTER TABLE tmp_reco_latest_context ADD PRIMARY KEY (scrip, frequency);

    DROP TEMPORARY TABLE IF EXISTS tmp_reco_recent_event;
    CREATE TEMPORARY TABLE tmp_reco_recent_event AS
    SELECT
        ranked.scrip,
        ranked.frequency,
        ranked.trade_date AS recent_signal_date,
        ranked.trade_signal
    FROM (
        SELECT
            ordered.*,
            @event_row := IF(
                @event_latest_key = CONCAT(ordered.scrip, '|', ordered.frequency),
                @event_row + 1,
                1
            ) AS event_row,
            @event_latest_key := CONCAT(ordered.scrip, '|', ordered.frequency)
                AS event_latest_key_set
        FROM (
            SELECT *
            FROM tmp_reco_events
            ORDER BY scrip, frequency, trade_date DESC
        ) ordered
        CROSS JOIN (SELECT @event_latest_key := '', @event_row := 0) vars
    ) ranked
    WHERE ranked.event_row = 1;
    ALTER TABLE tmp_reco_recent_event ADD PRIMARY KEY (scrip, frequency);

    DROP TEMPORARY TABLE IF EXISTS tmp_reco_backtest_scored;
    CREATE TEMPORARY TABLE tmp_reco_backtest_scored AS
    SELECT
        m.*,
        s.`Rank` AS rank_value,
        UPPER(TRIM(s.`AssetClass`)) AS assetclass,
        recent.trade_signal,
        recent.recent_signal_date,
        latest.latest_date,
        latest.close_price,
        latest.ha_signal,
        latest.ha_trend,
        latest.sma_delta_trend,
        (
            total_rank.metric_rank / @metric_count
            + win_rank.metric_rank / @metric_count
            + avg_rank.metric_rank / @metric_count
            - 0.5 * drawdown_rank.metric_rank / @metric_count
        ) AS backtest_score
    FROM tmp_reco_metrics m
    JOIN tmp_reco_rank_total total_rank
      ON total_rank.scrip = m.scrip AND total_rank.frequency = m.frequency
    JOIN tmp_reco_rank_win win_rank
      ON win_rank.scrip = m.scrip AND win_rank.frequency = m.frequency
    JOIN tmp_reco_rank_avg avg_rank
      ON avg_rank.scrip = m.scrip AND avg_rank.frequency = m.frequency
    JOIN tmp_reco_rank_drawdown drawdown_rank
      ON drawdown_rank.scrip = m.scrip AND drawdown_rank.frequency = m.frequency
    JOIN `jstockdata_scrips` s
      ON s.`Scrip` = m.scrip
     AND UPPER(TRIM(COALESCE(s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(s.`RecoUniverseRank`, 999999) <= 1000
    LEFT JOIN tmp_reco_recent_event recent
      ON recent.scrip = m.scrip AND recent.frequency = m.frequency
    LEFT JOIN tmp_reco_latest_context latest
      ON latest.scrip = m.scrip AND latest.frequency = m.frequency;

    CREATE TABLE IF NOT EXISTS `jstockdata_backtest_summary` (
        `reco_type` VARCHAR(20) NOT NULL,
        `frequency` VARCHAR(20) NOT NULL,
        `scrip` VARCHAR(20) NOT NULL,
        `rank` INT NULL,
        `assetclass` VARCHAR(30) NULL,
        `trade_signal` VARCHAR(10) NULL,
        `recent_signal_date` INT NULL,
        `days_since_recent_signal` INT NULL,
        `close` DECIMAL(12,2) NULL,
        `ha_signal` VARCHAR(10) NULL,
        `ha_trend` VARCHAR(10) NULL,
        `sma_delta_trend` VARCHAR(10) NULL,
        `backtest_trades` INT NOT NULL,
        `backtest_win_rate_pct` DECIMAL(18,2) NULL,
        `backtest_total_return_pct` DECIMAL(18,2) NULL,
        `backtest_avg_trade_return_pct` DECIMAL(18,2) NULL,
        `backtest_worst_trade_pct` DECIMAL(18,2) NULL,
        PRIMARY KEY (`frequency`, `scrip`),
        INDEX `ix_backtest_summary_assetclass` (`frequency`, `assetclass`, `rank`),
        INDEX `ix_backtest_summary_signal` (`frequency`, `trade_signal`, `recent_signal_date`)
    ) ENGINE=InnoDB;

    CREATE TABLE IF NOT EXISTS `jstockdata_reco_backtest` (
        `reco_type` VARCHAR(20) NOT NULL,
        `frequency` VARCHAR(20) NOT NULL,
        `scrip` VARCHAR(20) NOT NULL,
        `rank` INT NULL,
        `assetclass` VARCHAR(30) NULL,
        `trade_signal` VARCHAR(10) NULL,
        `recent_signal_date` INT NULL,
        `days_since_recent_signal` INT NULL,
        `close` DECIMAL(12,2) NULL,
        `ha_signal` VARCHAR(10) NULL,
        `ha_trend` VARCHAR(10) NULL,
        `sma_delta_trend` VARCHAR(10) NULL,
        `backtest_trades` INT NOT NULL,
        `backtest_win_rate_pct` DECIMAL(18,2) NULL,
        `backtest_total_return_pct` DECIMAL(18,2) NULL,
        `backtest_avg_trade_return_pct` DECIMAL(18,2) NULL,
        `backtest_worst_trade_pct` DECIMAL(18,2) NULL,
        PRIMARY KEY (`frequency`, `scrip`),
        INDEX `ix_reco_backtest_assetclass` (`frequency`, `assetclass`, `rank`)
    ) ENGINE=InnoDB;

    ALTER TABLE `jstockdata_backtest_summary`
        MODIFY COLUMN `recent_signal_date` INT NULL;

    ALTER TABLE `jstockdata_reco_backtest`
        MODIFY COLUMN `recent_signal_date` INT NULL;

    TRUNCATE TABLE `jstockdata_backtest_summary`;
    TRUNCATE TABLE `jstockdata_reco_backtest`;

    INSERT INTO `jstockdata_backtest_summary` (
        reco_type, frequency, scrip, `rank`, assetclass, trade_signal,
        recent_signal_date, days_since_recent_signal, close, ha_signal, ha_trend,
        sma_delta_trend, backtest_trades, backtest_win_rate_pct,
        backtest_total_return_pct, backtest_avg_trade_return_pct,
        backtest_worst_trade_pct
    )
    SELECT
        'backtest' AS reco_type,
        frequency,
        scrip,
        rank_value AS `rank`,
        assetclass,
        trade_signal,
        recent_signal_date AS recent_signal_date,
        DATEDIFF(
            STR_TO_DATE(CAST(latest_date AS CHAR), '%Y%m%d'),
            STR_TO_DATE(CAST(recent_signal_date AS CHAR), '%Y%m%d')
        ) AS days_since_recent_signal,
        close_price AS close,
        ha_signal,
        ha_trend,
        sma_delta_trend,
        backtest_trades,
        CAST(ROUND(backtest_win_rate_pct, 2) AS DECIMAL(18,2)) AS backtest_win_rate_pct,
        CAST(ROUND(backtest_total_return_pct, 2) AS DECIMAL(18,2)) AS backtest_total_return_pct,
        CAST(ROUND(backtest_avg_trade_return_pct, 2) AS DECIMAL(18,2)) AS backtest_avg_trade_return_pct,
        CAST(ROUND(backtest_worst_trade_pct, 2) AS DECIMAL(18,2)) AS backtest_worst_trade_pct
    FROM tmp_reco_backtest_scored
    ORDER BY
        frequency,
        FIELD(assetclass, 'EQ', 'ETF'),
        backtest_score DESC,
        backtest_total_return_pct DESC,
        backtest_win_rate_pct DESC,
        scrip;

    DROP TEMPORARY TABLE IF EXISTS tmp_reco_backtest_ranked;
    CREATE TEMPORARY TABLE tmp_reco_backtest_ranked AS
    SELECT ranked.*
    FROM (
        SELECT
            b.*,
            @bucket_row := IF(
                @bucket_key = CONCAT(b.frequency, '|', b.assetclass),
                @bucket_row + 1,
                1
            ) AS bucket_row,
            @bucket_key := CONCAT(b.frequency, '|', b.assetclass) AS bucket_key_set
        FROM (
            SELECT *
            FROM tmp_reco_backtest_scored
            WHERE assetclass IN ('EQ', 'ETF')
            ORDER BY
                frequency,
                FIELD(assetclass, 'EQ', 'ETF'),
                backtest_score DESC,
                backtest_total_return_pct DESC,
                backtest_win_rate_pct DESC,
                scrip
        ) b
        CROSS JOIN (SELECT @bucket_key := '', @bucket_row := 0) vars
    ) ranked
    WHERE ranked.bucket_row <= 10;

    INSERT INTO `jstockdata_reco_backtest` (
        reco_type, frequency, scrip, `rank`, assetclass, trade_signal,
        recent_signal_date, days_since_recent_signal, close, ha_signal, ha_trend,
        sma_delta_trend, backtest_trades, backtest_win_rate_pct,
        backtest_total_return_pct, backtest_avg_trade_return_pct,
        backtest_worst_trade_pct
    )
    SELECT
        'backtest' AS reco_type,
        frequency,
        scrip,
        rank_value AS `rank`,
        assetclass,
        trade_signal,
        recent_signal_date AS recent_signal_date,
        DATEDIFF(
            STR_TO_DATE(CAST(latest_date AS CHAR), '%Y%m%d'),
            STR_TO_DATE(CAST(recent_signal_date AS CHAR), '%Y%m%d')
        ) AS days_since_recent_signal,
        close_price AS close,
        ha_signal,
        ha_trend,
        sma_delta_trend,
        backtest_trades,
        CAST(ROUND(backtest_win_rate_pct, 2) AS DECIMAL(18,2)) AS backtest_win_rate_pct,
        CAST(ROUND(backtest_total_return_pct, 2) AS DECIMAL(18,2)) AS backtest_total_return_pct,
        CAST(ROUND(backtest_avg_trade_return_pct, 2) AS DECIMAL(18,2)) AS backtest_avg_trade_return_pct,
        CAST(ROUND(backtest_worst_trade_pct, 2) AS DECIMAL(18,2)) AS backtest_worst_trade_pct
    FROM tmp_reco_backtest_ranked
    ORDER BY frequency, FIELD(assetclass, 'EQ', 'ETF'), bucket_row;

    -- SELECT *
    -- FROM `jstockdata_reco_backtest`
    -- ORDER BY
        -- frequency,
        -- FIELD(assetclass, 'EQ', 'ETF'),
        -- backtest_win_rate_pct DESC,
        -- backtest_total_return_pct DESC,
        -- `rank`,
        -- scrip;
END$$
DELIMITER ;


DROP PROCEDURE IF EXISTS `reco_trade`;
DELIMITER $$
CREATE DEFINER=`admin`@`%` PROCEDURE `reco_trade`()
BEGIN

SET @min_trades := 3;
SET @min_win_rate_pct := 60.0;
SET @max_signal_age_days := 30;
SET @rows_per_bucket := 10;

DROP TEMPORARY TABLE IF EXISTS tmp_reco_events;
CREATE TEMPORARY TABLE tmp_reco_events AS
SELECT
    h.`SCRIP` AS scrip,
    TRIM(REPLACE(h.`FREQUENCY`, '\r', '')) AS frequency,
    h.`DATE` AS trade_date,
    h.`Close` AS close_price,
    UPPER(TRIM(h.`Combined_Signal_Ind`)) AS trade_signal
FROM `jstockdata_hatrend_extend` h
JOIN `jstockdata_scrips` universe_s
  ON universe_s.`Scrip` = h.`SCRIP`
 AND UPPER(TRIM(COALESCE(universe_s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(universe_s.`RecoUniverseRank`, 999999) <= 1000
WHERE TRIM(REPLACE(h.`FREQUENCY`, '\r', '')) IN ('DAILY', 'WEEKLY')
  AND UPPER(TRIM(h.`Combined_Signal_Ind`)) IN ('BUY', 'SELL')
  AND h.`Close` > 0;

ALTER TABLE tmp_reco_events
    ADD INDEX ix_events (scrip, frequency, trade_date);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_events_seq;
CREATE TEMPORARY TABLE tmp_reco_events_seq AS
SELECT scrip, frequency, trade_date, close_price, trade_signal, event_seq
FROM (
    SELECT
        e.*,
        @event_seq := IF(@event_key = CONCAT(e.scrip, '|', e.frequency),
                         @event_seq + 1, 1) AS event_seq,
        @event_key := CONCAT(e.scrip, '|', e.frequency) AS event_key_set
    FROM (
        SELECT *
        FROM tmp_reco_events
        ORDER BY scrip, frequency, trade_date
    ) e
    CROSS JOIN (SELECT @event_key := '', @event_seq := 0) vars
) numbered;

ALTER TABLE tmp_reco_events_seq
    ADD INDEX ix_events_seq (scrip, frequency, event_seq);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_events_seq_sell;
CREATE TEMPORARY TABLE tmp_reco_events_seq_sell AS
SELECT * FROM tmp_reco_events_seq;
ALTER TABLE tmp_reco_events_seq_sell
    ADD INDEX ix_events_seq_sell (scrip, frequency, event_seq);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_trades;
CREATE TEMPORARY TABLE tmp_reco_trades AS
SELECT
    buy_event.scrip,
    buy_event.frequency,
    buy_event.trade_date AS entry_date,
    sell_event.trade_date AS exit_date,
    buy_event.close_price AS entry_price,
    sell_event.close_price AS exit_price,
    sell_event.close_price / buy_event.close_price AS return_ratio,
    ((sell_event.close_price / buy_event.close_price) - 1) * 100 AS return_pct
FROM tmp_reco_events_seq buy_event
JOIN tmp_reco_events_seq_sell sell_event
  ON sell_event.scrip = buy_event.scrip
 AND sell_event.frequency = buy_event.frequency
 AND sell_event.event_seq = buy_event.event_seq + 1
WHERE buy_event.trade_signal = 'BUY'
  AND sell_event.trade_signal = 'SELL';

ALTER TABLE tmp_reco_trades
    ADD INDEX ix_trades (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_metrics;
CREATE TEMPORARY TABLE tmp_reco_metrics AS
SELECT
    t.scrip,
    t.frequency,
    COUNT(*) AS backtest_trades,
    SUM(t.return_pct > 0) * 100.0 / COUNT(*) AS backtest_win_rate_pct,
    (EXP(SUM(LN(t.return_ratio))) - 1) * 100 AS backtest_total_return_pct,
    AVG(t.return_pct) AS backtest_avg_trade_return_pct,
    MIN(t.return_pct) AS backtest_worst_trade_pct
FROM tmp_reco_trades t
GROUP BY t.scrip, t.frequency
HAVING COUNT(*) >= @min_trades;

ALTER TABLE tmp_reco_metrics
    ADD PRIMARY KEY (scrip, frequency);

SET @metric_count := (SELECT COUNT(*) FROM tmp_reco_metrics);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_rank_total;
CREATE TEMPORARY TABLE tmp_reco_rank_total AS
SELECT scrip, frequency, @rn_total := @rn_total + 1 AS metric_rank
FROM (
    SELECT scrip, frequency
    FROM tmp_reco_metrics
    ORDER BY backtest_total_return_pct, scrip, frequency
) ordered
CROSS JOIN (SELECT @rn_total := 0) vars;
ALTER TABLE tmp_reco_rank_total ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_rank_win;
CREATE TEMPORARY TABLE tmp_reco_rank_win AS
SELECT scrip, frequency, @rn_win := @rn_win + 1 AS metric_rank
FROM (
    SELECT scrip, frequency
    FROM tmp_reco_metrics
    ORDER BY backtest_win_rate_pct, scrip, frequency
) ordered
CROSS JOIN (SELECT @rn_win := 0) vars;
ALTER TABLE tmp_reco_rank_win ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_rank_avg;
CREATE TEMPORARY TABLE tmp_reco_rank_avg AS
SELECT scrip, frequency, @rn_avg := @rn_avg + 1 AS metric_rank
FROM (
    SELECT scrip, frequency
    FROM tmp_reco_metrics
    ORDER BY backtest_avg_trade_return_pct, scrip, frequency
) ordered
CROSS JOIN (SELECT @rn_avg := 0) vars;
ALTER TABLE tmp_reco_rank_avg ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_rank_drawdown;
CREATE TEMPORARY TABLE tmp_reco_rank_drawdown AS
SELECT scrip, frequency, @rn_drawdown := @rn_drawdown + 1 AS metric_rank
FROM (
    SELECT scrip, frequency
    FROM tmp_reco_metrics
    ORDER BY ABS(backtest_worst_trade_pct), scrip, frequency
) ordered
CROSS JOIN (SELECT @rn_drawdown := 0) vars;
ALTER TABLE tmp_reco_rank_drawdown ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_signal_status;
CREATE TEMPORARY TABLE tmp_reco_signal_status AS
SELECT
    scrip,
    frequency,
    SUBSTRING_INDEX(GROUP_CONCAT(trade_signal ORDER BY trade_date DESC), ',', 1)
        AS trade_signal,
    MAX(trade_date) AS recent_signal_date
FROM tmp_reco_events
GROUP BY scrip, frequency;
ALTER TABLE tmp_reco_signal_status ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_latest_history;
CREATE TEMPORARY TABLE tmp_reco_latest_history AS
SELECT
    h.`SCRIP` AS scrip,
    TRIM(REPLACE(h.`FREQUENCY`, '\r', '')) AS frequency,
    MAX(h.`DATE`) AS latest_date
FROM `jstockdata_hatrend_extend` h
JOIN `jstockdata_scrips` universe_s
  ON universe_s.`Scrip` = h.`SCRIP`
 AND UPPER(TRIM(COALESCE(universe_s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(universe_s.`RecoUniverseRank`, 999999) <= 1000
WHERE TRIM(REPLACE(h.`FREQUENCY`, '\r', '')) IN ('DAILY', 'WEEKLY')
GROUP BY h.`SCRIP`, TRIM(REPLACE(h.`FREQUENCY`, '\r', ''));
ALTER TABLE tmp_reco_latest_history ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_backtest_scored;
CREATE TEMPORARY TABLE tmp_reco_backtest_scored AS
SELECT
    m.*,
    s.`Rank` AS rank_value,
    UPPER(TRIM(s.`AssetClass`)) AS assetclass,
    status.trade_signal,
    status.recent_signal_date,
    history.latest_date,
    (
        total_rank.metric_rank / @metric_count
        + win_rank.metric_rank / @metric_count
        + avg_rank.metric_rank / @metric_count
        - 0.5 * drawdown_rank.metric_rank / @metric_count
    ) AS backtest_score
FROM tmp_reco_metrics m
JOIN tmp_reco_rank_total total_rank
  ON total_rank.scrip = m.scrip AND total_rank.frequency = m.frequency
JOIN tmp_reco_rank_win win_rank
  ON win_rank.scrip = m.scrip AND win_rank.frequency = m.frequency
JOIN tmp_reco_rank_avg avg_rank
  ON avg_rank.scrip = m.scrip AND avg_rank.frequency = m.frequency
JOIN tmp_reco_rank_drawdown drawdown_rank
  ON drawdown_rank.scrip = m.scrip AND drawdown_rank.frequency = m.frequency
JOIN `jstockdata_scrips` s
  ON s.`Scrip` = m.scrip
 AND UPPER(TRIM(COALESCE(s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(s.`RecoUniverseRank`, 999999) <= 1000
LEFT JOIN tmp_reco_signal_status status
  ON status.scrip = m.scrip AND status.frequency = m.frequency
LEFT JOIN tmp_reco_latest_history history
  ON history.scrip = m.scrip AND history.frequency = m.frequency;

DROP TEMPORARY TABLE IF EXISTS tmp_reco_backtest_ranked;
CREATE TEMPORARY TABLE tmp_reco_backtest_ranked AS
SELECT ranked.*
FROM (
    SELECT
        b.*,
        @bucket_row := IF(
            @bucket_key = CONCAT(b.frequency, '|', b.assetclass),
            @bucket_row + 1,
            1
        ) AS bucket_row,
        @bucket_key := CONCAT(b.frequency, '|', b.assetclass) AS bucket_key_set
    FROM (
        SELECT *
        FROM tmp_reco_backtest_scored
        WHERE assetclass IN ('EQ', 'ETF')
        ORDER BY
            frequency,
            FIELD(assetclass, 'EQ', 'ETF'),
            backtest_score DESC,
            backtest_total_return_pct DESC,
            backtest_win_rate_pct DESC,
            scrip
    ) b
    CROSS JOIN (SELECT @bucket_key := '', @bucket_row := 0) vars
) ranked
WHERE ranked.bucket_row <= @rows_per_bucket;

DROP TEMPORARY TABLE IF EXISTS tmp_reco_latest_recent;
CREATE TEMPORARY TABLE tmp_reco_latest_recent AS
SELECT
    r.`SCRIP` AS scrip,
    TRIM(REPLACE(r.`Frequency`, '\r', '')) AS frequency,
    MAX(r.`DATE`) AS latest_date
FROM `jstockdata_harecent` r
WHERE TRIM(REPLACE(r.`Frequency`, '\r', '')) IN ('DAILY', 'WEEKLY')
GROUP BY r.`SCRIP`, TRIM(REPLACE(r.`Frequency`, '\r', ''));
ALTER TABLE tmp_reco_latest_recent ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_latest_extend;
CREATE TEMPORARY TABLE tmp_reco_latest_extend AS
SELECT
    e.`SCRIP` AS scrip,
    TRIM(REPLACE(e.`FREQUENCY`, '\r', '')) AS frequency,
    MAX(e.`DATE`) AS latest_date
FROM `jstockdata_harecent_extend` e
WHERE TRIM(REPLACE(e.`FREQUENCY`, '\r', '')) IN ('DAILY', 'WEEKLY')
GROUP BY e.`SCRIP`, TRIM(REPLACE(e.`FREQUENCY`, '\r', ''));
ALTER TABLE tmp_reco_latest_extend ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_trade_candidates;
CREATE TEMPORARY TABLE tmp_reco_trade_candidates AS
SELECT
    b.*,
    r.`CLOSE` AS current_close,
    UPPER(TRIM(COALESCE(r.`HATrendSignal`, ''))) AS ha_signal,
    UPPER(TRIM(COALESCE(r.`HATrendCorrect`, ''))) AS ha_trend,
    UPPER(TRIM(COALESCE(e.`SMADeltaTrend`, ''))) AS sma_delta_trend,
    DATEDIFF(
        STR_TO_DATE(CAST(b.latest_date AS CHAR), '%Y%m%d'),
        STR_TO_DATE(CAST(b.recent_signal_date AS CHAR), '%Y%m%d')
    ) + 1 AS inclusive_signal_age
FROM tmp_reco_backtest_scored b
JOIN tmp_reco_latest_recent latest_recent
  ON latest_recent.scrip = b.scrip
 AND latest_recent.frequency = b.frequency
JOIN `jstockdata_harecent` r
  ON r.`SCRIP` = latest_recent.scrip
 AND TRIM(REPLACE(r.`Frequency`, '\r', '')) = latest_recent.frequency
 AND r.`DATE` = latest_recent.latest_date
JOIN tmp_reco_latest_extend latest_extend
  ON latest_extend.scrip = b.scrip
 AND latest_extend.frequency = b.frequency
JOIN `jstockdata_harecent_extend` e
  ON e.`SCRIP` = latest_extend.scrip
 AND TRIM(REPLACE(e.`FREQUENCY`, '\r', '')) = latest_extend.frequency
 AND e.`DATE` = latest_extend.latest_date
WHERE b.assetclass IN ('EQ', 'ETF')
  AND b.backtest_win_rate_pct >= @min_win_rate_pct
  AND b.trade_signal = 'BUY'
  AND UPPER(TRIM(COALESCE(e.`Combined_Signal`, ''))) = 'BUY'
  AND (
      UPPER(TRIM(COALESCE(r.`HATrendSignal`, ''))) = 'BUY'
      OR UPPER(TRIM(COALESCE(r.`HATrendCorrect`, ''))) = 'GREEN'
  )
  AND DATEDIFF(
        STR_TO_DATE(CAST(b.latest_date AS CHAR), '%Y%m%d'),
        STR_TO_DATE(CAST(b.recent_signal_date AS CHAR), '%Y%m%d')
      ) + 1 <= @max_signal_age_days;

DROP TEMPORARY TABLE IF EXISTS tmp_reco_trade_ranked;
CREATE TEMPORARY TABLE tmp_reco_trade_ranked AS
SELECT ranked.*
FROM (
    SELECT
        t.*,
        @trade_bucket_row := IF(
            @trade_bucket_key = CONCAT(t.frequency, '|', t.assetclass),
            @trade_bucket_row + 1,
            1
        ) AS bucket_row,
        @trade_bucket_key := CONCAT(t.frequency, '|', t.assetclass)
            AS bucket_key_set
    FROM (
        SELECT *
        FROM tmp_reco_trade_candidates
        ORDER BY
            frequency,
            FIELD(assetclass, 'EQ', 'ETF'),
            backtest_score DESC,
            backtest_total_return_pct DESC,
            backtest_win_rate_pct DESC,
            COALESCE(rank_value, 999999),
            scrip
    ) t
    CROSS JOIN (SELECT @trade_bucket_key := '', @trade_bucket_row := 0) vars
) ranked
WHERE ranked.bucket_row <= @rows_per_bucket;

CREATE TABLE IF NOT EXISTS `jstockdata_reco_trade` (
    `reco_type` VARCHAR(20) NOT NULL,
    `frequency` VARCHAR(20) NOT NULL,
    `scrip` VARCHAR(20) NOT NULL,
    `rank` INT NULL,
    `assetclass` VARCHAR(30) NULL,
    `trade_signal` VARCHAR(10) NULL,
    `recent_signal_date` DATE NULL,
    `days_since_recent_signal` INT NULL,
    `close` DECIMAL(12,2) NULL,
    `ha_signal` VARCHAR(10) NULL,
    `ha_trend` VARCHAR(10) NULL,
    `sma_delta_trend` VARCHAR(10) NULL,
    `backtest_trades` INT NOT NULL,
    `backtest_win_rate_pct` DECIMAL(18,2) NULL,
    `backtest_total_return_pct` DECIMAL(18,2) NULL,
    `backtest_avg_trade_return_pct` DECIMAL(18,2) NULL,
    `backtest_worst_trade_pct` DECIMAL(18,2) NULL,
    PRIMARY KEY (`frequency`, `scrip`),
    INDEX `ix_reco_trade_assetclass` (`frequency`, `assetclass`, `rank`)
) ENGINE=InnoDB;

TRUNCATE TABLE `jstockdata_reco_trade`;

INSERT INTO `jstockdata_reco_trade` (
    reco_type, frequency, scrip, `rank`, assetclass, trade_signal,
    recent_signal_date, days_since_recent_signal, close, ha_signal, ha_trend,
    sma_delta_trend, backtest_trades, backtest_win_rate_pct,
    backtest_total_return_pct, backtest_avg_trade_return_pct,
    backtest_worst_trade_pct
)
SELECT
    'trade' AS reco_type,
    frequency,
    scrip,
    rank_value AS `rank`,
    assetclass,
    'BUY' AS trade_signal,
    STR_TO_DATE(CAST(recent_signal_date AS CHAR), '%Y%m%d') AS recent_signal_date,
    inclusive_signal_age AS days_since_recent_signal,
    current_close AS close,
    ha_signal,
    ha_trend,
    sma_delta_trend,
    backtest_trades,
    CAST(ROUND(backtest_win_rate_pct, 2) AS DECIMAL(18,2)) AS backtest_win_rate_pct,
    CAST(ROUND(backtest_total_return_pct, 2) AS DECIMAL(18,2)) AS backtest_total_return_pct,
    CAST(ROUND(backtest_avg_trade_return_pct, 2) AS DECIMAL(18,2)) AS backtest_avg_trade_return_pct,
    CAST(ROUND(backtest_worst_trade_pct, 2) AS DECIMAL(18,2)) AS backtest_worst_trade_pct
FROM tmp_reco_trade_ranked
ORDER BY frequency, FIELD(assetclass, 'EQ', 'ETF'), bucket_row;

-- SELECT *
-- FROM `jstockdata_reco_trade`
-- ORDER BY frequency, FIELD(assetclass, 'EQ', 'ETF'), `rank`, scrip;

END$$
DELIMITER ;


DROP PROCEDURE IF EXISTS `reco_invest`;
DELIMITER $$
CREATE DEFINER=`admin`@`%` PROCEDURE `reco_invest`()
BEGIN

SET @min_trades := 3;
SET @min_win_rate_pct := 60.0;
SET @min_total_return_pct := 0.0;
SET @max_signal_age_days := 30;
SET @rows_per_bucket := 10;

DROP TEMPORARY TABLE IF EXISTS tmp_reco_events;
CREATE TEMPORARY TABLE tmp_reco_events AS
SELECT
    h.`SCRIP` AS scrip,
    TRIM(REPLACE(h.`FREQUENCY`, '\r', '')) AS frequency,
    h.`DATE` AS trade_date,
    h.`Close` AS close_price,
    UPPER(TRIM(h.`Combined_Signal_Ind`)) AS trade_signal
FROM `jstockdata_hatrend_extend` h
JOIN `jstockdata_scrips` universe_s
  ON universe_s.`Scrip` = h.`SCRIP`
 AND UPPER(TRIM(COALESCE(universe_s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(universe_s.`RecoUniverseRank`, 999999) <= 1000
WHERE TRIM(REPLACE(h.`FREQUENCY`, '\r', '')) IN ('DAILY', 'WEEKLY')
  AND UPPER(TRIM(h.`Combined_Signal_Ind`)) IN ('BUY', 'SELL')
  AND h.`Close` > 0;

ALTER TABLE tmp_reco_events
    ADD INDEX ix_events (scrip, frequency, trade_date);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_events_seq;
CREATE TEMPORARY TABLE tmp_reco_events_seq AS
SELECT scrip, frequency, trade_date, close_price, trade_signal, event_seq
FROM (
    SELECT
        e.*,
        @event_seq := IF(@event_key = CONCAT(e.scrip, '|', e.frequency),
                         @event_seq + 1, 1) AS event_seq,
        @event_key := CONCAT(e.scrip, '|', e.frequency) AS event_key_set
    FROM (
        SELECT *
        FROM tmp_reco_events
        ORDER BY scrip, frequency, trade_date
    ) e
    CROSS JOIN (SELECT @event_key := '', @event_seq := 0) vars
) numbered;

ALTER TABLE tmp_reco_events_seq
    ADD INDEX ix_events_seq (scrip, frequency, event_seq);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_events_seq_sell;
CREATE TEMPORARY TABLE tmp_reco_events_seq_sell AS
SELECT * FROM tmp_reco_events_seq;
ALTER TABLE tmp_reco_events_seq_sell
    ADD INDEX ix_events_seq_sell (scrip, frequency, event_seq);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_trades;
CREATE TEMPORARY TABLE tmp_reco_trades AS
SELECT
    buy_event.scrip,
    buy_event.frequency,
    buy_event.trade_date AS entry_date,
    sell_event.trade_date AS exit_date,
    buy_event.close_price AS entry_price,
    sell_event.close_price AS exit_price,
    sell_event.close_price / buy_event.close_price AS return_ratio,
    ((sell_event.close_price / buy_event.close_price) - 1) * 100 AS return_pct
FROM tmp_reco_events_seq buy_event
JOIN tmp_reco_events_seq_sell sell_event
  ON sell_event.scrip = buy_event.scrip
 AND sell_event.frequency = buy_event.frequency
 AND sell_event.event_seq = buy_event.event_seq + 1
WHERE buy_event.trade_signal = 'BUY'
  AND sell_event.trade_signal = 'SELL';

ALTER TABLE tmp_reco_trades
    ADD INDEX ix_trades (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_metrics;
CREATE TEMPORARY TABLE tmp_reco_metrics AS
SELECT
    t.scrip,
    t.frequency,
    COUNT(*) AS backtest_trades,
    SUM(t.return_pct > 0) * 100.0 / COUNT(*) AS backtest_win_rate_pct,
    (EXP(SUM(LN(t.return_ratio))) - 1) * 100 AS backtest_total_return_pct,
    AVG(t.return_pct) AS backtest_avg_trade_return_pct,
    MIN(t.return_pct) AS backtest_worst_trade_pct
FROM tmp_reco_trades t
GROUP BY t.scrip, t.frequency
HAVING COUNT(*) >= @min_trades;

ALTER TABLE tmp_reco_metrics
    ADD PRIMARY KEY (scrip, frequency);

SET @metric_count := (SELECT COUNT(*) FROM tmp_reco_metrics);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_rank_total;
CREATE TEMPORARY TABLE tmp_reco_rank_total AS
SELECT scrip, frequency, @rn_total := @rn_total + 1 AS metric_rank
FROM (
    SELECT scrip, frequency
    FROM tmp_reco_metrics
    ORDER BY backtest_total_return_pct, scrip, frequency
) ordered
CROSS JOIN (SELECT @rn_total := 0) vars;
ALTER TABLE tmp_reco_rank_total ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_rank_win;
CREATE TEMPORARY TABLE tmp_reco_rank_win AS
SELECT scrip, frequency, @rn_win := @rn_win + 1 AS metric_rank
FROM (
    SELECT scrip, frequency
    FROM tmp_reco_metrics
    ORDER BY backtest_win_rate_pct, scrip, frequency
) ordered
CROSS JOIN (SELECT @rn_win := 0) vars;
ALTER TABLE tmp_reco_rank_win ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_rank_avg;
CREATE TEMPORARY TABLE tmp_reco_rank_avg AS
SELECT scrip, frequency, @rn_avg := @rn_avg + 1 AS metric_rank
FROM (
    SELECT scrip, frequency
    FROM tmp_reco_metrics
    ORDER BY backtest_avg_trade_return_pct, scrip, frequency
) ordered
CROSS JOIN (SELECT @rn_avg := 0) vars;
ALTER TABLE tmp_reco_rank_avg ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_rank_drawdown;
CREATE TEMPORARY TABLE tmp_reco_rank_drawdown AS
SELECT scrip, frequency, @rn_drawdown := @rn_drawdown + 1 AS metric_rank
FROM (
    SELECT scrip, frequency
    FROM tmp_reco_metrics
    ORDER BY ABS(backtest_worst_trade_pct), scrip, frequency
) ordered
CROSS JOIN (SELECT @rn_drawdown := 0) vars;
ALTER TABLE tmp_reco_rank_drawdown ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_signal_status;
CREATE TEMPORARY TABLE tmp_reco_signal_status AS
SELECT
    scrip,
    frequency,
    SUBSTRING_INDEX(GROUP_CONCAT(trade_signal ORDER BY trade_date DESC), ',', 1)
        AS trade_signal,
    MAX(trade_date) AS recent_signal_date
FROM tmp_reco_events
GROUP BY scrip, frequency;
ALTER TABLE tmp_reco_signal_status ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_latest_history;
CREATE TEMPORARY TABLE tmp_reco_latest_history AS
SELECT
    h.`SCRIP` AS scrip,
    TRIM(REPLACE(h.`FREQUENCY`, '\r', '')) AS frequency,
    MAX(h.`DATE`) AS latest_date
FROM `jstockdata_hatrend_extend` h
JOIN `jstockdata_scrips` universe_s
  ON universe_s.`Scrip` = h.`SCRIP`
 AND UPPER(TRIM(COALESCE(universe_s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(universe_s.`RecoUniverseRank`, 999999) <= 1000
WHERE TRIM(REPLACE(h.`FREQUENCY`, '\r', '')) IN ('DAILY', 'WEEKLY')
GROUP BY h.`SCRIP`, TRIM(REPLACE(h.`FREQUENCY`, '\r', ''));
ALTER TABLE tmp_reco_latest_history ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_backtest_scored;
CREATE TEMPORARY TABLE tmp_reco_backtest_scored AS
SELECT
    m.*,
    s.`Rank` AS rank_value,
    UPPER(TRIM(s.`AssetClass`)) AS assetclass,
    status.trade_signal,
    status.recent_signal_date,
    history.latest_date,
    (
        total_rank.metric_rank / @metric_count
        + win_rank.metric_rank / @metric_count
        + avg_rank.metric_rank / @metric_count
        - 0.5 * drawdown_rank.metric_rank / @metric_count
    ) AS backtest_score
FROM tmp_reco_metrics m
JOIN tmp_reco_rank_total total_rank
  ON total_rank.scrip = m.scrip AND total_rank.frequency = m.frequency
JOIN tmp_reco_rank_win win_rank
  ON win_rank.scrip = m.scrip AND win_rank.frequency = m.frequency
JOIN tmp_reco_rank_avg avg_rank
  ON avg_rank.scrip = m.scrip AND avg_rank.frequency = m.frequency
JOIN tmp_reco_rank_drawdown drawdown_rank
  ON drawdown_rank.scrip = m.scrip AND drawdown_rank.frequency = m.frequency
JOIN `jstockdata_scrips` s
  ON s.`Scrip` = m.scrip
 AND UPPER(TRIM(COALESCE(s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(s.`RecoUniverseRank`, 999999) <= 1000
LEFT JOIN tmp_reco_signal_status status
  ON status.scrip = m.scrip AND status.frequency = m.frequency
LEFT JOIN tmp_reco_latest_history history
  ON history.scrip = m.scrip AND history.frequency = m.frequency;

DROP TEMPORARY TABLE IF EXISTS tmp_reco_backtest_ranked;
CREATE TEMPORARY TABLE tmp_reco_backtest_ranked AS
SELECT ranked.*
FROM (
    SELECT
        b.*,
        @bucket_row := IF(
            @bucket_key = CONCAT(b.frequency, '|', b.assetclass),
            @bucket_row + 1,
            1
        ) AS bucket_row,
        @bucket_key := CONCAT(b.frequency, '|', b.assetclass) AS bucket_key_set
    FROM (
        SELECT *
        FROM tmp_reco_backtest_scored
        WHERE assetclass IN ('EQ', 'ETF')
        ORDER BY
            frequency,
            FIELD(assetclass, 'EQ', 'ETF'),
            backtest_score DESC,
            backtest_total_return_pct DESC,
            backtest_win_rate_pct DESC,
            scrip
    ) b
    CROSS JOIN (SELECT @bucket_key := '', @bucket_row := 0) vars
) ranked
WHERE ranked.bucket_row <= @rows_per_bucket;

DROP TEMPORARY TABLE IF EXISTS tmp_reco_latest_recent;
CREATE TEMPORARY TABLE tmp_reco_latest_recent AS
SELECT
    r.`SCRIP` AS scrip,
    TRIM(REPLACE(r.`Frequency`, '\r', '')) AS frequency,
    MAX(r.`DATE`) AS latest_date
FROM `jstockdata_harecent` r
WHERE TRIM(REPLACE(r.`Frequency`, '\r', '')) IN ('DAILY', 'WEEKLY')
GROUP BY r.`SCRIP`, TRIM(REPLACE(r.`Frequency`, '\r', ''));
ALTER TABLE tmp_reco_latest_recent ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_latest_extend;
CREATE TEMPORARY TABLE tmp_reco_latest_extend AS
SELECT
    e.`SCRIP` AS scrip,
    TRIM(REPLACE(e.`FREQUENCY`, '\r', '')) AS frequency,
    MAX(e.`DATE`) AS latest_date
FROM `jstockdata_harecent_extend` e
WHERE TRIM(REPLACE(e.`FREQUENCY`, '\r', '')) IN ('DAILY', 'WEEKLY')
GROUP BY e.`SCRIP`, TRIM(REPLACE(e.`FREQUENCY`, '\r', ''));
ALTER TABLE tmp_reco_latest_extend ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_current_trade;
CREATE TEMPORARY TABLE tmp_reco_current_trade AS
SELECT
    b.scrip,
    b.frequency,
    r.`CLOSE` AS current_close,
    UPPER(TRIM(COALESCE(r.`HATrendSignal`, ''))) AS ha_signal,
    UPPER(TRIM(COALESCE(r.`HATrendCorrect`, ''))) AS ha_trend,
    UPPER(TRIM(COALESCE(e.`SMADeltaTrend`, ''))) AS sma_delta_trend
FROM tmp_reco_backtest_scored b
JOIN tmp_reco_latest_recent latest_recent
  ON latest_recent.scrip = b.scrip
 AND latest_recent.frequency = b.frequency
JOIN `jstockdata_harecent` r
  ON r.`SCRIP` = latest_recent.scrip
 AND TRIM(REPLACE(r.`Frequency`, '\r', '')) = latest_recent.frequency
 AND r.`DATE` = latest_recent.latest_date
JOIN tmp_reco_latest_extend latest_extend
  ON latest_extend.scrip = b.scrip
 AND latest_extend.frequency = b.frequency
JOIN `jstockdata_harecent_extend` e
  ON e.`SCRIP` = latest_extend.scrip
 AND TRIM(REPLACE(e.`FREQUENCY`, '\r', '')) = latest_extend.frequency
 AND e.`DATE` = latest_extend.latest_date
WHERE b.assetclass IN ('EQ', 'ETF')
  AND b.backtest_win_rate_pct >= @min_win_rate_pct
  AND b.trade_signal = 'BUY'
  AND UPPER(TRIM(COALESCE(e.`Combined_Signal`, ''))) = 'BUY'
  AND (
      UPPER(TRIM(COALESCE(r.`HATrendSignal`, ''))) = 'BUY'
      OR UPPER(TRIM(COALESCE(r.`HATrendCorrect`, ''))) = 'GREEN'
  )
  AND DATEDIFF(
        STR_TO_DATE(CAST(b.latest_date AS CHAR), '%Y%m%d'),
        STR_TO_DATE(CAST(b.recent_signal_date AS CHAR), '%Y%m%d')
      ) + 1 <= @max_signal_age_days;
ALTER TABLE tmp_reco_current_trade ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_backtest_weekly;
CREATE TEMPORARY TABLE tmp_reco_backtest_weekly AS
SELECT * FROM tmp_reco_backtest_scored WHERE frequency = 'WEEKLY';
ALTER TABLE tmp_reco_backtest_weekly ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_current_trade_weekly;
CREATE TEMPORARY TABLE tmp_reco_current_trade_weekly AS
SELECT * FROM tmp_reco_current_trade WHERE frequency = 'WEEKLY';
ALTER TABLE tmp_reco_current_trade_weekly ADD PRIMARY KEY (scrip, frequency);

DROP TEMPORARY TABLE IF EXISTS tmp_reco_invest_candidates;
CREATE TEMPORARY TABLE tmp_reco_invest_candidates AS
SELECT
    daily.scrip,
    daily.rank_value,
    daily.assetclass,
    IF(daily_trade.scrip IS NOT NULL OR weekly_trade.scrip IS NOT NULL,
       'BUY', 'WAIT') AS investment_signal,
    GREATEST(daily.recent_signal_date, weekly.recent_signal_date)
        AS investment_recent_signal_date,
    LEAST(
        DATEDIFF(
            STR_TO_DATE(CAST(daily.latest_date AS CHAR), '%Y%m%d'),
            STR_TO_DATE(CAST(daily.recent_signal_date AS CHAR), '%Y%m%d')
        ) + 1,
        DATEDIFF(
            STR_TO_DATE(CAST(weekly.latest_date AS CHAR), '%Y%m%d'),
            STR_TO_DATE(CAST(weekly.recent_signal_date AS CHAR), '%Y%m%d')
        ) + 1
    ) AS investment_signal_age,
    COALESCE(daily_trade.current_close, weekly_trade.current_close) AS current_close,
    COALESCE(daily_trade.ha_signal, weekly_trade.ha_signal) AS ha_signal,
    COALESCE(daily_trade.ha_trend, weekly_trade.ha_trend) AS ha_trend,
    COALESCE(daily_trade.sma_delta_trend, weekly_trade.sma_delta_trend)
        AS sma_delta_trend,
    daily.backtest_trades + weekly.backtest_trades AS backtest_trades,
    (daily.backtest_win_rate_pct + weekly.backtest_win_rate_pct) / 2
        AS backtest_win_rate_pct,
    daily.backtest_total_return_pct + weekly.backtest_total_return_pct
        AS backtest_total_return_pct,
    (daily.backtest_avg_trade_return_pct + weekly.backtest_avg_trade_return_pct) / 2
        AS backtest_avg_trade_return_pct,
    LEAST(daily.backtest_worst_trade_pct, weekly.backtest_worst_trade_pct)
        AS backtest_worst_trade_pct,
    daily.backtest_score + weekly.backtest_score AS combined_score
FROM tmp_reco_backtest_scored daily
JOIN tmp_reco_backtest_weekly weekly
  ON weekly.scrip = daily.scrip
 AND weekly.frequency = 'WEEKLY'
LEFT JOIN tmp_reco_current_trade daily_trade
  ON daily_trade.scrip = daily.scrip
 AND daily_trade.frequency = 'DAILY'
LEFT JOIN tmp_reco_current_trade_weekly weekly_trade
  ON weekly_trade.scrip = daily.scrip
 AND weekly_trade.frequency = 'WEEKLY'
WHERE daily.frequency = 'DAILY'
  AND daily.assetclass IN ('EQ', 'ETF')
  AND daily.backtest_win_rate_pct >= @min_win_rate_pct
  AND weekly.backtest_win_rate_pct >= @min_win_rate_pct
  AND daily.backtest_total_return_pct >= @min_total_return_pct
  AND weekly.backtest_total_return_pct >= @min_total_return_pct;

DROP TEMPORARY TABLE IF EXISTS tmp_reco_invest_ranked;
CREATE TEMPORARY TABLE tmp_reco_invest_ranked AS
SELECT ranked.*
FROM (
    SELECT
        i.*,
        @invest_bucket_row := IF(
            @invest_bucket_key = i.assetclass,
            @invest_bucket_row + 1,
            1
        ) AS bucket_row,
        @invest_bucket_key := i.assetclass AS bucket_key_set
    FROM (
        SELECT *
        FROM tmp_reco_invest_candidates
        ORDER BY
            FIELD(assetclass, 'EQ', 'ETF'),
            combined_score DESC,
            backtest_win_rate_pct DESC,
            backtest_total_return_pct DESC,
            COALESCE(rank_value, 999999),
            scrip
    ) i
    CROSS JOIN (SELECT @invest_bucket_key := '', @invest_bucket_row := 0) vars
) ranked
WHERE ranked.bucket_row <= @rows_per_bucket;

CREATE TABLE IF NOT EXISTS `jstockdata_reco_invest` (
    `reco_type` VARCHAR(20) NOT NULL,
    `frequency` VARCHAR(20) NOT NULL,
    `scrip` VARCHAR(20) NOT NULL,
    `rank` INT NULL,
    `assetclass` VARCHAR(30) NULL,
    `trade_signal` VARCHAR(10) NULL,
    `recent_signal_date` DATE NULL,
    `days_since_recent_signal` INT NULL,
    `close` DECIMAL(12,2) NULL,
    `ha_signal` VARCHAR(10) NULL,
    `ha_trend` VARCHAR(10) NULL,
    `sma_delta_trend` VARCHAR(10) NULL,
    `backtest_trades` INT NOT NULL,
    `backtest_win_rate_pct` DECIMAL(18,2) NULL,
    `backtest_total_return_pct` DECIMAL(18,2) NULL,
    `backtest_avg_trade_return_pct` DECIMAL(18,2) NULL,
    `backtest_worst_trade_pct` DECIMAL(18,2) NULL,
    PRIMARY KEY (`frequency`, `scrip`),
    INDEX `ix_reco_invest_assetclass` (`frequency`, `assetclass`, `rank`)
) ENGINE=InnoDB;

TRUNCATE TABLE `jstockdata_reco_invest`;

INSERT INTO `jstockdata_reco_invest` (
    reco_type, frequency, scrip, `rank`, assetclass, trade_signal,
    recent_signal_date, days_since_recent_signal, close, ha_signal, ha_trend,
    sma_delta_trend, backtest_trades, backtest_win_rate_pct,
    backtest_total_return_pct, backtest_avg_trade_return_pct,
    backtest_worst_trade_pct
)
SELECT
    'investment' AS reco_type,
    'DAILY+WEEKLY' AS frequency,
    scrip,
    rank_value AS `rank`,
    assetclass,
    investment_signal AS trade_signal,
    STR_TO_DATE(CAST(investment_recent_signal_date AS CHAR), '%Y%m%d')
        AS recent_signal_date,
    investment_signal_age AS days_since_recent_signal,
    current_close AS close,
    ha_signal,
    ha_trend,
    sma_delta_trend,
    backtest_trades,
    CAST(ROUND(backtest_win_rate_pct, 2) AS DECIMAL(18,2)) AS backtest_win_rate_pct,
    CAST(ROUND(backtest_total_return_pct, 2) AS DECIMAL(18,2)) AS backtest_total_return_pct,
    CAST(ROUND(backtest_avg_trade_return_pct, 2) AS DECIMAL(18,2)) AS backtest_avg_trade_return_pct,
    CAST(ROUND(backtest_worst_trade_pct, 2) AS DECIMAL(18,2)) AS backtest_worst_trade_pct
FROM tmp_reco_invest_ranked
ORDER BY FIELD(assetclass, 'EQ', 'ETF'), bucket_row;

-- SELECT *
-- FROM `jstockdata_reco_invest`
-- ORDER BY FIELD(assetclass, 'EQ', 'ETF'), `rank`, scrip;

END$$
DELIMITER ;


DROP PROCEDURE IF EXISTS `reco_options`;
DELIMITER $$
CREATE DEFINER=`admin`@`%` PROCEDURE `reco_options`()
BEGIN

    DECLARE v_target_date DATE;

    DECLARE v_month_start DATE;

    DECLARE v_expiration_date DATE;



    SET v_target_date = DATE_ADD(CURDATE(), INTERVAL 35 DAY);

    SET v_month_start = DATE_ADD(LAST_DAY(DATE_SUB(v_target_date, INTERVAL 1 MONTH)), INTERVAL 1 DAY);

    SET v_expiration_date = DATE_ADD(

        v_month_start,

        INTERVAL (MOD(4 - WEEKDAY(v_month_start) + 7, 7) + 14) DAY

    );



    TRUNCATE TABLE `jstockdata_reco_options`;



    DROP TEMPORARY TABLE IF EXISTS `tmp_option_base`;

    CREATE TEMPORARY TABLE `tmp_option_base` AS

    SELECT

        w.`SCRIP` AS `scrip`,

        s.`Rank` AS `rank_value`,

        UPPER(TRIM(s.`AssetClass`)) AS `assetclass`,

        w.`Close` AS `close_price`,

        CASE

            WHEN w.`Combined_Signal_Ind` IN ('BUY', 'SELL')

                THEN CAST(w.`DATE` AS CHAR)

            WHEN d.`Combined_Signal_Ind` IN ('BUY', 'SELL')

                THEN CAST(d.`DATE` AS CHAR)

            ELSE CAST(w.`DATE` AS CHAR)

        END AS `signal_date`,

        CASE

            WHEN w.`Combined_Signal_Ind` IN ('BUY', 'SELL') THEN 'WEEKLY'

            WHEN d.`Combined_Signal_Ind` IN ('BUY', 'SELL') THEN 'DAILY'

            ELSE 'WEEKLY'

        END AS `signal_chart`,

        CASE

            WHEN w.`Combined_Signal_Ind` IN ('BUY', 'SELL') THEN 'FRESH'

            ELSE 'ACTIVE'

        END AS `signal_status`,

        w.`Combined_Signal` AS `direction`,

        w.`Combined_Signal` AS `weekly_combined_signal`,

        d.`Combined_Signal` AS `daily_combined_signal`,

        CASE

            WHEN w.`Close` < 25 THEN 0.50

            WHEN w.`Close` < 200 THEN 1.00

            WHEN w.`Close` < 500 THEN 5.00

            ELSE 10.00

        END AS `strike_increment`,

        LEAST(

            85,

            58

            + CASE WHEN w.`Combined_Signal_Ind` IN ('BUY', 'SELL') THEN 10 ELSE 0 END

            + CASE WHEN w.`LODeltaSignal` = d.`LODeltaSignal` THEN 6 ELSE 0 END

            + CASE

                WHEN w.`Combined_Signal` = 'BUY' AND d.`HARSIValue` BETWEEN 45 AND 70 THEN 5

                WHEN w.`Combined_Signal` = 'SELL' AND d.`HARSIValue` BETWEEN 30 AND 55 THEN 5

                ELSE 0

              END

            + CASE

                WHEN w.`Combined_Signal` = 'BUY' AND h.`HARallySlope` > 0 THEN 4

                WHEN w.`Combined_Signal` = 'SELL' AND h.`HARallySlope` < 0 THEN 4

                ELSE 0

              END

        ) AS `probability_pct`,

        LEAST(

            100,

            45

            + CASE WHEN w.`Combined_Signal_Ind` IN ('BUY', 'SELL') THEN 20 ELSE 0 END

            + CASE WHEN w.`LODeltaSignal` = d.`LODeltaSignal` THEN 10 ELSE 0 END

            + CASE WHEN h.`CLOSE` * h.`volume` >= 100000000 THEN 10 ELSE 0 END

            + CASE

                WHEN w.`Combined_Signal` = 'BUY' AND h.`HARallySlope` > 0 THEN 10

                WHEN w.`Combined_Signal` = 'SELL' AND h.`HARallySlope` < 0 THEN 10

                ELSE 0

              END

        ) AS `recommendation_score`

    FROM `jstockdata_harecent_extend` w

    JOIN `jstockdata_harecent_extend` d

      ON d.`SCRIP` = w.`SCRIP`

     AND d.`FREQUENCY` = 'DAILY'

    JOIN `jstockdata_harecent` h

      ON h.`SCRIP` = w.`SCRIP`

     AND TRIM(REPLACE(h.`Frequency`, '\r', '')) = 'WEEKLY'

    JOIN `jstockdata_scrips` s

      ON s.`Scrip` = w.`SCRIP`

    WHERE w.`FREQUENCY` = 'WEEKLY'

      AND UPPER(TRIM(s.`AssetClass`)) IN ('EQ', 'ETF')
      AND UPPER(TRIM(COALESCE(s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(s.`RecoUniverseRank`, 999999) <= 1000

      AND w.`Combined_Signal` IN ('BUY', 'SELL')

      AND d.`Combined_Signal` = w.`Combined_Signal`

      AND w.`Close` > 0;



    DROP TEMPORARY TABLE IF EXISTS `tmp_option_base_sell`;

    CREATE TEMPORARY TABLE `tmp_option_base_sell` AS

    SELECT * FROM `tmp_option_base`;



    INSERT INTO `jstockdata_reco_options` (

        `generated_at`,

        `scrip`,

        `rank`,

        `assetclass`,

        `close_price`,

        `signal_date`,

        `signal_chart`,

        `signal_status`,

        `direction`,

        `option_trade`,

        `option_type`,

        `option_side`,

        `moneyness_target`,

        `strike_price`,

        `exp_date`,

        `dte`,

        `premium`,

        `premium_source`,

        `premium_roi_pct`,

        `implied_volatility`,

        `probability_pct`,

        `probability_type`,

        `recommendation_score`,

        `weekly_combined_signal`,

        `daily_combined_signal`,

        `market_data_provider`,

        `market_data_asof`

    )

    SELECT

        DATE_FORMAT(CURDATE(), '%Y%m%d'),

        `scrip`,

        `rank_value`,

        `assetclass`,

        `close_price`,

        `signal_date`,

        `signal_chart`,

        `signal_status`,

        `direction`,

        CASE WHEN `direction` = 'BUY' THEN 'BUY CALL' ELSE 'BUY PUT' END,

        CASE WHEN `direction` = 'BUY' THEN 'CALL' ELSE 'PUT' END,

        'BUY',

        'ATM-ITM',

        CASE

            WHEN `direction` = 'BUY' THEN FLOOR(`close_price` / `strike_increment`) * `strike_increment`

            ELSE CEIL(`close_price` / `strike_increment`) * `strike_increment`

        END,

        DATE_FORMAT(v_expiration_date, '%Y%m%d'),

        DATEDIFF(v_expiration_date, CURDATE()),

        NULL,

        NULL,

        NULL,

        NULL,

        `probability_pct`,

        'DIRECTIONAL_HEURISTIC',

        `recommendation_score`,

        `weekly_combined_signal`,

        `daily_combined_signal`,

        NULL,

        NULL

    FROM `tmp_option_base`

    UNION ALL

    SELECT

        DATE_FORMAT(CURDATE(), '%Y%m%d'),

        `scrip`,

        `rank_value`,

        `assetclass`,

        `close_price`,

        `signal_date`,

        `signal_chart`,

        `signal_status`,

        `direction`,

        CASE WHEN `direction` = 'BUY' THEN 'SELL PUT' ELSE 'SELL CALL' END,

        CASE WHEN `direction` = 'BUY' THEN 'PUT' ELSE 'CALL' END,

        'SELL',

        'OTM',

        CASE

            WHEN `direction` = 'BUY' THEN FLOOR((`close_price` * 0.95) / `strike_increment`) * `strike_increment`

            ELSE CEIL((`close_price` * 1.05) / `strike_increment`) * `strike_increment`

        END,

        DATE_FORMAT(v_expiration_date, '%Y%m%d'),

        DATEDIFF(v_expiration_date, CURDATE()),

        NULL,

        NULL,

        NULL,

        NULL,

        LEAST(90, `probability_pct` + 5),

        'DIRECTIONAL_HEURISTIC',

        `recommendation_score`,

        `weekly_combined_signal`,

        `daily_combined_signal`,

        NULL,

        NULL

    FROM `tmp_option_base_sell`;



    DROP TEMPORARY TABLE IF EXISTS `tmp_option_base`;

    DROP TEMPORARY TABLE IF EXISTS `tmp_option_base_sell`;



    -- SELECT

        -- `opportunity_id`,

        -- `generated_at`,

        -- `scrip`,

        -- `rank`,

        -- `assetclass`,

        -- `close_price`,

        -- `signal_date`,

        -- `signal_chart`,

        -- `signal_status`,

        -- `direction`,

        -- `option_trade`,

        -- `option_type`,

        -- `option_side`,

        -- `moneyness_target`,

        -- `strike_price`,

        -- `exp_date`,

        -- `dte`,

        -- `premium`,

        -- `premium_source`,

        -- `premium_roi_pct`,

        -- `implied_volatility`,

        -- `probability_pct`,

        -- `probability_type`,

        -- `recommendation_score`,

        -- `weekly_combined_signal`,

        -- `daily_combined_signal`,

        -- `market_data_provider`,

        -- `market_data_asof`

    -- FROM `jstockdata_reco_options`

    -- ORDER BY

        -- FIELD(`signal_status`, 'FRESH', 'ACTIVE'),

        -- `recommendation_score` DESC,

        -- `probability_pct` DESC,

        -- `rank`,

        -- `scrip`,

        -- `option_trade`;

END$$
DELIMITER ;


DROP PROCEDURE IF EXISTS `reco_projection_refresh`;
DELIMITER $$
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
END$$
DELIMITER ;


DROP PROCEDURE IF EXISTS `reco_momentum_refresh`;
DELIMITER $$
CREATE DEFINER=`admin`@`%` PROCEDURE `reco_momentum_refresh`()
BEGIN
  DECLARE v_generated_at DATETIME DEFAULT NOW();

  CREATE TABLE IF NOT EXISTS `jstockdata_reco_momentum_signal` (
    `scrip` VARCHAR(20) NOT NULL,
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
    PRIMARY KEY (`scrip`, `frequency`, `signal_date`),
    KEY `ix_momentum_frequency_score` (`frequency`, `momentum_direction`, `momentum_score`),
    KEY `ix_momentum_phase` (`frequency`, `momentum_phase`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

  TRUNCATE TABLE `jstockdata_reco_momentum_signal`;

  DROP TABLE IF EXISTS `jstockdata_momentum_work_base`;
  CREATE TABLE `jstockdata_momentum_work_base` AS
  SELECT
    ordered.*,
    @row_num := IF(@row_key = CONCAT(ordered.scrip, '|', ordered.frequency), @row_num + 1, 1) AS seq_num,
    @row_key := CONCAT(ordered.scrip, '|', ordered.frequency) AS seq_key
  FROM (
    SELECT
      h.`SCRIP` AS scrip,
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
    JOIN `jstockdata_scrips` universe_s
      ON universe_s.`Scrip` = h.`SCRIP`
     AND UPPER(TRIM(COALESCE(universe_s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(universe_s.`RecoUniverseRank`, 999999) <= 1000
    JOIN `jstockdata_harecent_extend` e
      ON e.`SCRIP` = h.`SCRIP`
     AND e.`DATE` = h.`DATE`
     AND TRIM(REPLACE(e.`FREQUENCY`, '\r', '')) = TRIM(REPLACE(h.`Frequency`, '\r', ''))
    WHERE TRIM(REPLACE(h.`Frequency`, '\r', '')) IN ('DAILY', 'WEEKLY')
    ORDER BY h.`SCRIP`, TRIM(REPLACE(h.`Frequency`, '\r', '')), h.`DATE`
  ) ordered
  CROSS JOIN (SELECT @row_key := '', @row_num := 0) vars;

  ALTER TABLE `jstockdata_momentum_work_base`
    ADD PRIMARY KEY (`scrip`, `frequency`, `seq_num`),
    ADD KEY `ix_tmp_momentum_latest` (`scrip`, `frequency`, `signal_date`);

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
  LEFT JOIN `jstockdata_momentum_work_base` p1 ON p1.scrip = b.scrip AND p1.frequency = b.frequency AND p1.seq_num = b.seq_num - 1
  LEFT JOIN `jstockdata_momentum_work_base` p2 ON p2.scrip = b.scrip AND p2.frequency = b.frequency AND p2.seq_num = b.seq_num - 2
  LEFT JOIN `jstockdata_momentum_work_base` p3 ON p3.scrip = b.scrip AND p3.frequency = b.frequency AND p3.seq_num = b.seq_num - 3
  LEFT JOIN `jstockdata_momentum_work_base` p4 ON p4.scrip = b.scrip AND p4.frequency = b.frequency AND p4.seq_num = b.seq_num - 4
  LEFT JOIN `jstockdata_momentum_work_base` p5 ON p5.scrip = b.scrip AND p5.frequency = b.frequency AND p5.seq_num = b.seq_num - 5;

  INSERT INTO `jstockdata_reco_momentum_signal` (
    scrip, frequency, signal_date, close_price, momentum_score, momentum_direction,
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
    c.scrip,
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
           AND c.Combined_Signal = 'BUY'
           AND c.LODeltaSignal = 'BUY'
           AND COALESCE(c.HARSIValue, 50) < 75
           AND COALESCE(c.momentum_acceleration, 0) >= 0 THEN 'BULLISH_ACCELERATING'
      WHEN c.raw_momentum_score >= 18
           AND COALESCE(c.HARallySeq, 0) BETWEEN 1 AND 3
           AND COALESCE(c.momentum_acceleration, 0) >= 0 THEN 'EARLY'
      WHEN c.raw_momentum_score >= 18
           AND (COALESCE(c.HARSIValue, 50) >= 75 OR COALESCE(c.HARallySeq, 0) >= 8) THEN 'MATURE'
      WHEN c.raw_momentum_score >= 18
           AND COALESCE(c.momentum_acceleration, 0) < 0 THEN 'WEAKENING'
      WHEN c.raw_momentum_score <= -18
           AND c.Combined_Signal = 'SELL'
           AND c.LODeltaSignal = 'SELL'
           AND COALESCE(c.HARSIValue, 50) > 25
           AND COALESCE(c.momentum_acceleration, 0) <= 0 THEN 'BEARISH_ACCELERATING'
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
END$$
DELIMITER ;


DROP PROCEDURE IF EXISTS `reco_basket_refresh`;
DELIMITER $$
CREATE DEFINER=`admin`@`%` PROCEDURE `reco_basket_refresh`()
BEGIN
    DECLARE v_batch_id CHAR(36);
    SET v_batch_id = UUID();

    CREATE TABLE IF NOT EXISTS `jstockdata_reco_basket_current` (
        `scrip` VARCHAR(20) NOT NULL,
        `assetclass` VARCHAR(30) NOT NULL,
        `basket_rank` INT NOT NULL,
        `target_weight_pct` DECIMAL(8,2) NOT NULL,
        `basket_score` DECIMAL(18,2) NOT NULL,
        `daily_signal` VARCHAR(10) NULL,
        `weekly_signal` VARCHAR(10) NULL,
        `daily_signal_ind` VARCHAR(10) NULL,
        `weekly_signal_ind` VARCHAR(10) NULL,
        `daily_sma_delta_trend` VARCHAR(10) NULL,
        `weekly_sma_delta_trend` VARCHAR(10) NULL,
        `backtest_win_rate_pct` DECIMAL(18,2) NULL,
        `backtest_total_return_pct` DECIMAL(18,2) NULL,
        `recent_signal_date` DATE NULL,
        `days_since_recent_signal` INT NULL,
        `opened_at` DATETIME NOT NULL,
        `updated_at` DATETIME NOT NULL,
        PRIMARY KEY (`scrip`),
        INDEX `ix_basket_current_rank` (`assetclass`, `basket_rank`)
    ) ENGINE=InnoDB;

    CREATE TABLE IF NOT EXISTS `jstockdata_reco_basket_actions` (
        `action_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        `batch_id` CHAR(36) NOT NULL,
        `scrip` VARCHAR(20) NOT NULL,
        `assetclass` VARCHAR(30) NOT NULL,
        `action` VARCHAR(20) NOT NULL,
        `reason` VARCHAR(255) NOT NULL,
        `previous_rank` INT NULL,
        `proposed_rank` INT NULL,
        `previous_weight_pct` DECIMAL(8,2) NULL,
        `proposed_weight_pct` DECIMAL(8,2) NULL,
        `previous_score` DECIMAL(18,2) NULL,
        `proposed_score` DECIMAL(18,2) NULL,
        `approval_status` VARCHAR(30) NOT NULL DEFAULT 'PENDING_APPROVAL',
        `created_at` DATETIME NOT NULL,
        PRIMARY KEY (`action_id`),
        INDEX `ix_basket_actions_batch` (`batch_id`, `action`),
        INDEX `ix_basket_actions_status` (`approval_status`, `created_at`)
    ) ENGINE=InnoDB;

    CREATE TABLE IF NOT EXISTS `jstockdata_reco_basket_history` (
        `history_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        `batch_id` CHAR(36) NOT NULL,
        `scrip` VARCHAR(20) NOT NULL,
        `assetclass` VARCHAR(30) NOT NULL,
        `basket_rank` INT NOT NULL,
        `target_weight_pct` DECIMAL(8,2) NOT NULL,
        `basket_score` DECIMAL(18,2) NOT NULL,
        `daily_signal` VARCHAR(10) NULL,
        `weekly_signal` VARCHAR(10) NULL,
        `daily_signal_ind` VARCHAR(10) NULL,
        `weekly_signal_ind` VARCHAR(10) NULL,
        `backtest_win_rate_pct` DECIMAL(18,2) NULL,
        `backtest_total_return_pct` DECIMAL(18,2) NULL,
        `snapshot_at` DATETIME NOT NULL,
        PRIMARY KEY (`history_id`),
        INDEX `ix_basket_history_batch` (`batch_id`, `assetclass`, `basket_rank`)
    ) ENGINE=InnoDB;

    DROP TEMPORARY TABLE IF EXISTS tmp_basket_latest_signal;
    CREATE TEMPORARY TABLE tmp_basket_latest_signal AS
    SELECT
        latest.scrip,
        latest.frequency,
        UPPER(TRIM(COALESCE(h.`Combined_Signal`, ''))) AS combined_signal,
        UPPER(TRIM(COALESCE(h.`Combined_Signal_Ind`, ''))) AS combined_signal_ind,
        UPPER(TRIM(COALESCE(h.`SMADeltaTrend`, ''))) AS sma_delta_trend,
        h.`DATE` AS signal_date
    FROM (
        SELECT
            `SCRIP` AS scrip,
            TRIM(REPLACE(`FREQUENCY`, '\r', '')) AS frequency,
            MAX(`DATE`) AS max_date
        FROM `jstockdata_harecent_extend`
        WHERE TRIM(REPLACE(`FREQUENCY`, '\r', '')) IN ('DAILY', 'WEEKLY')
        GROUP BY `SCRIP`, TRIM(REPLACE(`FREQUENCY`, '\r', ''))
    ) latest
    JOIN `jstockdata_harecent_extend` h
      ON h.`SCRIP` = latest.scrip
     AND TRIM(REPLACE(h.`FREQUENCY`, '\r', '')) = latest.frequency
     AND h.`DATE` = latest.max_date;
    ALTER TABLE tmp_basket_latest_signal ADD PRIMARY KEY (scrip, frequency);

    DROP TEMPORARY TABLE IF EXISTS tmp_basket_signal_weekly;
    CREATE TEMPORARY TABLE tmp_basket_signal_weekly AS
    SELECT * FROM tmp_basket_latest_signal WHERE frequency = 'WEEKLY';
    ALTER TABLE tmp_basket_signal_weekly ADD PRIMARY KEY (scrip, frequency);

    DROP TEMPORARY TABLE IF EXISTS tmp_basket_candidates;
    CREATE TEMPORARY TABLE tmp_basket_candidates AS
    SELECT
        s.`Scrip` AS scrip,
        UPPER(TRIM(s.`AssetClass`)) AS assetclass,
        daily.combined_signal AS daily_signal,
        weekly.combined_signal AS weekly_signal,
        daily.combined_signal_ind AS daily_signal_ind,
        weekly.combined_signal_ind AS weekly_signal_ind,
        daily.sma_delta_trend AS daily_sma_delta_trend,
        weekly.sma_delta_trend AS weekly_sma_delta_trend,
        COALESCE(inv.backtest_win_rate_pct, trade_stats.backtest_win_rate_pct,
                 backtest_stats.backtest_win_rate_pct, 0) AS backtest_win_rate_pct,
        COALESCE(inv.backtest_total_return_pct, trade_stats.backtest_total_return_pct,
                 backtest_stats.backtest_total_return_pct, 0) AS backtest_total_return_pct,
        COALESCE(trade_stats.recent_signal_date, inv.recent_signal_date,
                 backtest_stats.recent_signal_date) AS recent_signal_date,
        COALESCE(trade_stats.days_since_recent_signal, inv.days_since_recent_signal,
                 backtest_stats.days_since_recent_signal, 999) AS days_since_recent_signal,
        (
            COALESCE(inv.backtest_win_rate_pct, trade_stats.backtest_win_rate_pct,
                     backtest_stats.backtest_win_rate_pct, 0)
            + LEAST(
                GREATEST(
                    COALESCE(inv.backtest_total_return_pct,
                             trade_stats.backtest_total_return_pct,
                             backtest_stats.backtest_total_return_pct, 0),
                    -100
                ),
                200
              ) * 0.10
            + IF(inv.scrip IS NOT NULL, 15, 0)
            + IF(trade_stats.daily_trade = 1, 12, 0)
            + IF(trade_stats.weekly_trade = 1, 15, 0)
            + IF(daily.combined_signal = 'BUY', 8, -12)
            + IF(weekly.combined_signal = 'BUY', 12, -18)
            + IF(daily.combined_signal_ind = 'BUY', 5, 0)
            + IF(weekly.combined_signal_ind = 'BUY', 7, 0)
            - LEAST(
                COALESCE(trade_stats.days_since_recent_signal,
                         inv.days_since_recent_signal,
                         backtest_stats.days_since_recent_signal, 60),
                60
              ) * 0.20
        ) AS basket_score
    FROM `jstockdata_scrips` s
    JOIN tmp_basket_latest_signal daily
      ON daily.scrip = s.`Scrip` AND daily.frequency = 'DAILY'
    JOIN tmp_basket_signal_weekly weekly
      ON weekly.scrip = s.`Scrip` AND weekly.frequency = 'WEEKLY'
    LEFT JOIN `jstockdata_reco_invest` inv ON inv.scrip = s.`Scrip`
    LEFT JOIN (
        SELECT
            scrip,
            MAX(frequency = 'DAILY') AS daily_trade,
            MAX(frequency = 'WEEKLY') AS weekly_trade,
            MAX(backtest_win_rate_pct) AS backtest_win_rate_pct,
            MAX(backtest_total_return_pct) AS backtest_total_return_pct,
            MAX(recent_signal_date) AS recent_signal_date,
            MIN(days_since_recent_signal) AS days_since_recent_signal
        FROM `jstockdata_reco_trade`
        GROUP BY scrip
    ) trade_stats ON trade_stats.scrip = s.`Scrip`
    LEFT JOIN (
        SELECT
            scrip,
            MAX(backtest_win_rate_pct) AS backtest_win_rate_pct,
            MAX(backtest_total_return_pct) AS backtest_total_return_pct,
            MAX(recent_signal_date) AS recent_signal_date,
            MIN(days_since_recent_signal) AS days_since_recent_signal
        FROM `jstockdata_reco_backtest`
        GROUP BY scrip
    ) backtest_stats ON backtest_stats.scrip = s.`Scrip`
    WHERE UPPER(TRIM(s.`AssetClass`)) IN ('EQ', 'ETF')
      AND UPPER(TRIM(COALESCE(s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(s.`RecoUniverseRank`, 999999) <= 1000
      AND (
          inv.scrip IS NOT NULL
          OR trade_stats.scrip IS NOT NULL
          OR (
              backtest_stats.scrip IS NOT NULL
              AND backtest_stats.backtest_win_rate_pct >= 60
          )
      )
      AND NOT (
          daily.combined_signal_ind = 'SELL'
          OR weekly.combined_signal_ind = 'SELL'
          OR (daily.combined_signal = 'SELL' AND weekly.combined_signal = 'SELL')
      )
      AND (
          daily.combined_signal = 'BUY'
          OR weekly.combined_signal = 'BUY'
      );
    ALTER TABLE tmp_basket_candidates ADD PRIMARY KEY (scrip);

    DROP TEMPORARY TABLE IF EXISTS tmp_basket_ranked;
    CREATE TEMPORARY TABLE tmp_basket_ranked AS
    SELECT ranked.*
    FROM (
        SELECT
            c.*,
            @basket_rank := IF(
                @basket_assetclass = c.assetclass,
                @basket_rank + 1,
                1
            ) AS basket_rank,
            @basket_assetclass := c.assetclass AS assetclass_set
        FROM (
            SELECT *
            FROM tmp_basket_candidates
            ORDER BY FIELD(assetclass, 'EQ', 'ETF'), basket_score DESC, scrip
        ) c
        CROSS JOIN (SELECT @basket_assetclass := '', @basket_rank := 0) vars
    ) ranked
    WHERE ranked.basket_rank <= 10;
    ALTER TABLE tmp_basket_ranked ADD PRIMARY KEY (scrip);

    SET @basket_target_count := (SELECT COUNT(*) FROM tmp_basket_ranked);

    DROP TEMPORARY TABLE IF EXISTS tmp_basket_target;
    CREATE TEMPORARY TABLE tmp_basket_target AS
    SELECT
        r.*,
        CAST(100.0 / NULLIF(@basket_target_count, 0) AS DECIMAL(8,2))
            AS target_weight_pct
    FROM tmp_basket_ranked r;
    ALTER TABLE tmp_basket_target ADD PRIMARY KEY (scrip);

    DROP TEMPORARY TABLE IF EXISTS tmp_basket_previous;
    CREATE TEMPORARY TABLE tmp_basket_previous AS
    SELECT * FROM `jstockdata_reco_basket_current`;
    ALTER TABLE tmp_basket_previous ADD PRIMARY KEY (scrip);

    INSERT INTO `jstockdata_reco_basket_actions` (
        batch_id, scrip, assetclass, action, reason, previous_rank,
        proposed_rank, previous_weight_pct, proposed_weight_pct,
        previous_score, proposed_score, approval_status, created_at
    )
    SELECT
        v_batch_id, current_basket.scrip, current_basket.assetclass, 'SELL',
        'No longer eligible or displaced by a stronger candidate',
        current_basket.basket_rank, NULL, current_basket.target_weight_pct, 0,
        current_basket.basket_score, NULL, 'PENDING_APPROVAL', NOW()
    FROM tmp_basket_previous current_basket
    LEFT JOIN tmp_basket_target target ON target.scrip = current_basket.scrip
    WHERE target.scrip IS NULL;

    INSERT INTO `jstockdata_reco_basket_actions` (
        batch_id, scrip, assetclass, action, reason, previous_rank,
        proposed_rank, previous_weight_pct, proposed_weight_pct,
        previous_score, proposed_score, approval_status, created_at
    )
    SELECT
        v_batch_id, target.scrip, target.assetclass, 'BUY',
        'New eligible high-scoring basket candidate',
        NULL, target.basket_rank, 0, target.target_weight_pct,
        NULL, target.basket_score, 'PENDING_APPROVAL', NOW()
    FROM tmp_basket_target target
    LEFT JOIN tmp_basket_previous current_basket
      ON current_basket.scrip = target.scrip
    WHERE current_basket.scrip IS NULL;

    INSERT INTO `jstockdata_reco_basket_actions` (
        batch_id, scrip, assetclass, action, reason, previous_rank,
        proposed_rank, previous_weight_pct, proposed_weight_pct,
        previous_score, proposed_score, approval_status, created_at
    )
    SELECT
        v_batch_id, target.scrip, target.assetclass,
        IF(target.daily_signal = 'SELL' AND target.weekly_signal = 'BUY',
           'TAPER', 'HOLD'),
        IF(target.daily_signal = 'SELL' AND target.weekly_signal = 'BUY',
           'DAILY momentum is weakening while WEEKLY remains BUY',
           'Remains an eligible top-ranked basket holding'),
        current_basket.basket_rank, target.basket_rank,
        current_basket.target_weight_pct, target.target_weight_pct,
        current_basket.basket_score, target.basket_score,
        'PENDING_APPROVAL', NOW()
    FROM tmp_basket_target target
    JOIN tmp_basket_previous current_basket
      ON current_basket.scrip = target.scrip;

    TRUNCATE TABLE `jstockdata_reco_basket_current`;

    INSERT INTO `jstockdata_reco_basket_current` (
        scrip, assetclass, basket_rank, target_weight_pct, basket_score,
        daily_signal, weekly_signal, daily_signal_ind, weekly_signal_ind,
        daily_sma_delta_trend, weekly_sma_delta_trend,
        backtest_win_rate_pct, backtest_total_return_pct,
        recent_signal_date, days_since_recent_signal, opened_at, updated_at
    )
    SELECT
        target.scrip, target.assetclass, target.basket_rank,
        target.target_weight_pct, ROUND(target.basket_score, 2),
        target.daily_signal, target.weekly_signal,
        target.daily_signal_ind, target.weekly_signal_ind,
        target.daily_sma_delta_trend, target.weekly_sma_delta_trend,
        ROUND(target.backtest_win_rate_pct, 2),
        ROUND(target.backtest_total_return_pct, 2),
        target.recent_signal_date, target.days_since_recent_signal,
        COALESCE(previous_basket.opened_at, NOW()), NOW()
    FROM tmp_basket_target target
    LEFT JOIN tmp_basket_previous previous_basket
      ON previous_basket.scrip = target.scrip;

    INSERT INTO `jstockdata_reco_basket_history` (
        batch_id, scrip, assetclass, basket_rank, target_weight_pct,
        basket_score, daily_signal, weekly_signal, daily_signal_ind,
        weekly_signal_ind, backtest_win_rate_pct,
        backtest_total_return_pct, snapshot_at
    )
    SELECT
        v_batch_id, scrip, assetclass, basket_rank, target_weight_pct,
        basket_score, daily_signal, weekly_signal, daily_signal_ind,
        weekly_signal_ind, backtest_win_rate_pct,
        backtest_total_return_pct, NOW()
    FROM `jstockdata_reco_basket_current`;
--
--     SELECT *
--     FROM `jstockdata_reco_basket_current`
--     ORDER BY FIELD(assetclass, 'EQ', 'ETF'), basket_rank;

    -- SELECT *
    -- FROM `jstockdata_reco_basket_actions`
    -- WHERE batch_id = v_batch_id
    -- ORDER BY FIELD(action, 'SELL', 'TAPER', 'BUY', 'HOLD'), assetclass, scrip;
END$$
DELIMITER ;


DROP PROCEDURE IF EXISTS `reco_weekly_target_refresh`;
DELIMITER $$
CREATE DEFINER=`admin`@`%` PROCEDURE `reco_weekly_target_refresh`()
BEGIN
  DECLARE v_generated_at DATETIME DEFAULT NOW();

  CREATE TABLE IF NOT EXISTS `jstockdata_reco_weekly_target_recos` (
    `reco_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `generated_at` DATETIME NOT NULL,
    `reco_category` VARCHAR(20) NOT NULL,
    `account_scope` VARCHAR(40) NOT NULL,
    `target_rank` INT NOT NULL,
    `scrip` VARCHAR(20) NOT NULL,
    `assetclass` VARCHAR(30) NULL,
    `source_table` VARCHAR(64) NOT NULL,
    `frequency` VARCHAR(20) NULL,
    `trade_signal` VARCHAR(10) NULL,
    `direction` VARCHAR(10) NULL,
    `option_trade` VARCHAR(20) NULL,
    `option_type` VARCHAR(4) NULL,
    `option_side` VARCHAR(4) NULL,
    `strike_price` DECIMAL(12,2) NULL,
    `exp_date` CHAR(8) NULL,
    `dte` INT NULL,
    `premium` DECIMAL(12,4) NULL,
    `premium_roi_pct` DECIMAL(10,4) NULL,
    `current_price` DECIMAL(12,2) NULL,
    `target_profit_min_pct` DECIMAL(6,2) NOT NULL DEFAULT 1.00,
    `target_profit_max_pct` DECIMAL(6,2) NOT NULL DEFAULT 3.00,
    `target_profit_pct` DECIMAL(10,2) NULL,
    `weeklyized_target_profit_pct` DECIMAL(10,2) NULL,
    `stop_review_pct` DECIMAL(10,2) NULL,
    `expected_return_pct` DECIMAL(10,2) NULL,
    `upward_projection_pct` DECIMAL(10,2) NULL,
    `upward_probability_pct` DECIMAL(6,2) NULL,
    `downward_projection_pct` DECIMAL(10,2) NULL,
    `downward_probability_pct` DECIMAL(6,2) NULL,
    `risk_reward_ratio` DECIMAL(10,2) NULL,
    `projection_sample_size` INT NULL,
    `projection_confidence_score` DECIMAL(6,2) NULL,
    `recommendation_score` DECIMAL(10,2) NULL,
    `news_swing_signal` VARCHAR(20) NULL,
    `news_options_signal` VARCHAR(30) NULL,
    `news_sentiment_score` DECIMAL(10,2) NULL,
    `news_catalyst_score` DECIMAL(10,2) NULL,
    `news_risk_score` DECIMAL(10,2) NULL,
    `news_top_headline` VARCHAR(500) NULL,
    `news_top_url` VARCHAR(1000) NULL,
    `target_band_status` VARCHAR(20) NOT NULL,
    `notes` VARCHAR(500) NULL,
    PRIMARY KEY (`reco_id`),
    KEY `ix_weekly_target_category_rank` (`reco_category`, `target_rank`),
    KEY `ix_weekly_target_scrip` (`scrip`),
    KEY `ix_weekly_target_generated` (`generated_at`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

  TRUNCATE TABLE `jstockdata_reco_weekly_target_recos`;

  INSERT INTO `jstockdata_reco_weekly_target_recos` (
    generated_at, reco_category, account_scope, target_rank, scrip, assetclass,
    source_table, frequency, trade_signal, direction, current_price,
    target_profit_pct, weeklyized_target_profit_pct, stop_review_pct, expected_return_pct, upward_projection_pct,
    upward_probability_pct, downward_projection_pct, downward_probability_pct,
    risk_reward_ratio, projection_sample_size, projection_confidence_score,
    recommendation_score, news_swing_signal, news_options_signal,
    news_sentiment_score, news_catalyst_score, news_risk_score,
    news_top_headline, news_top_url, target_band_status, notes
  )
  SELECT
    v_generated_at, 'EQT', 'Agentic Account', @eqt_rank := @eqt_rank + 1,
    ranked.scrip, ranked.assetclass, 'jstockdata_reco_trade', ranked.frequency,
    ranked.trade_signal, ranked.trade_signal, ranked.close,
    ranked.target_profit_pct, ranked.target_profit_pct, -2.50, ranked.expected_return_pct,
    ranked.upward_projection_pct, ranked.upward_probability_pct,
    ranked.downward_projection_pct, ranked.downward_probability_pct,
    ranked.risk_reward_ratio, ranked.projection_sample_size,
    ranked.projection_confidence_score, ranked.target_score,
    ranked.swing_news_signal, ranked.options_news_signal,
    ranked.news_sentiment_score, ranked.catalyst_score, ranked.news_risk_score,
    ranked.top_headline, ranked.top_url, ranked.target_band_status,
    CONCAT('Weekly 1%-3% target screen. ', ranked.target_band_status,
           '; news=', ranked.swing_news_signal,
           '; preserve 25% cash buffer and review live quote before order.')
  FROM (
    SELECT
      t.*,
      COALESCE(n.swing_news_signal, 'NO_RECENT_NEWS') AS swing_news_signal,
      COALESCE(n.options_news_signal, 'NO_RECENT_NEWS') AS options_news_signal,
      COALESCE(n.news_sentiment_score, 0) AS news_sentiment_score,
      COALESCE(n.catalyst_score, 0) AS catalyst_score,
      COALESCE(n.news_risk_score, 0) AS news_risk_score,
      n.top_headline,
      n.top_url,
      LEAST(3.00, GREATEST(1.00, COALESCE(t.expected_return_pct, t.upward_projection_pct, t.backtest_avg_trade_return_pct, 1.00))) AS target_profit_pct,
      CASE
        WHEN COALESCE(t.expected_return_pct, t.upward_projection_pct, 0) BETWEEN 1.00 AND 3.00 THEN 'IN_BAND'
        WHEN COALESCE(t.expected_return_pct, t.upward_projection_pct, 0) > 3.00 THEN 'ABOVE_BAND'
        ELSE 'NEAR_BAND'
      END AS target_band_status,
      (
        100
        - ABS(LEAST(3.00, GREATEST(1.00, COALESCE(t.expected_return_pct, t.upward_projection_pct, 1.00))) - 2.00) * 12
        + COALESCE(t.upward_probability_pct, 0) * 0.25
        - COALESCE(t.downward_probability_pct, 50) * 0.25
        + LEAST(COALESCE(t.risk_reward_ratio, 0), 8) * 3
        + COALESCE(t.projection_confidence_score, 0) * 0.30
        - GREATEST(COALESCE(t.expected_return_pct, 0) - 3.00, 0) * 4
        + CASE COALESCE(n.swing_news_signal, 'NO_RECENT_NEWS')
            WHEN 'BULLISH_CATALYST' THEN 8
            WHEN 'BEARISH_CATALYST' THEN -10
            WHEN 'NEWS_RISK_AVOID' THEN -25
            ELSE 0
          END
        + LEAST(8, GREATEST(-8, COALESCE(n.news_sentiment_score, 0) * 0.10))
        - LEAST(20, COALESCE(n.news_risk_score, 0) * 0.25)
      ) AS target_score
    FROM `jstockdata_reco_trade` t
    JOIN `jstockdata_scrips` s
      ON s.`Scrip` = t.scrip
     AND UPPER(TRIM(COALESCE(s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(s.`RecoUniverseRank`, 999999) <= 1000
    LEFT JOIN `jstockdata_reco_news_signal` n ON n.scrip = t.scrip
    WHERE t.assetclass = 'EQ'
      AND t.trade_signal = 'BUY'
      AND COALESCE(t.expected_return_pct, t.upward_projection_pct, t.backtest_avg_trade_return_pct, 0) >= 0.75
      AND COALESCE(t.upward_probability_pct, 0) >= 60
      AND COALESCE(t.downward_probability_pct, 100) <= 35
      AND COALESCE(t.risk_reward_ratio, 0) >= 1.20
      AND COALESCE(t.projection_confidence_score, 0) >= 45
      AND COALESCE(t.backtest_worst_trade_pct, -99) >= -12
    ORDER BY target_score DESC, FIELD(t.frequency, 'DAILY', 'WEEKLY'), t.`rank`, t.scrip
    LIMIT 10
  ) ranked
  CROSS JOIN (SELECT @eqt_rank := 0) vars;

  INSERT INTO `jstockdata_reco_weekly_target_recos` (
    generated_at, reco_category, account_scope, target_rank, scrip, assetclass,
    source_table, frequency, trade_signal, direction, current_price,
    target_profit_pct, weeklyized_target_profit_pct, stop_review_pct, expected_return_pct, upward_projection_pct,
    upward_probability_pct, downward_projection_pct, downward_probability_pct,
    risk_reward_ratio, projection_sample_size, projection_confidence_score,
    recommendation_score, news_swing_signal, news_options_signal,
    news_sentiment_score, news_catalyst_score, news_risk_score,
    news_top_headline, news_top_url, target_band_status, notes
  )
  SELECT
    v_generated_at, 'ETF', 'ETF Basket Review', @etf_rank := @etf_rank + 1,
    ranked.scrip, ranked.assetclass, 'jstockdata_reco_trade', ranked.frequency,
    ranked.trade_signal, ranked.trade_signal, ranked.close,
    ranked.target_profit_pct, ranked.target_profit_pct, -2.00, ranked.expected_return_pct,
    ranked.upward_projection_pct, ranked.upward_probability_pct,
    ranked.downward_projection_pct, ranked.downward_probability_pct,
    ranked.risk_reward_ratio, ranked.projection_sample_size,
    ranked.projection_confidence_score, ranked.target_score,
    ranked.swing_news_signal, ranked.options_news_signal,
    ranked.news_sentiment_score, ranked.catalyst_score, ranked.news_risk_score,
    ranked.top_headline, ranked.top_url, ranked.target_band_status,
    CONCAT('Weekly ETF 1%-3% target screen. ', ranked.target_band_status,
           '; news=', ranked.swing_news_signal,
           '; use basket sizing and review live spread/liquidity.')
  FROM (
    SELECT
      t.*,
      COALESCE(n.swing_news_signal, 'NO_RECENT_NEWS') AS swing_news_signal,
      COALESCE(n.options_news_signal, 'NO_RECENT_NEWS') AS options_news_signal,
      COALESCE(n.news_sentiment_score, 0) AS news_sentiment_score,
      COALESCE(n.catalyst_score, 0) AS catalyst_score,
      COALESCE(n.news_risk_score, 0) AS news_risk_score,
      n.top_headline,
      n.top_url,
      LEAST(3.00, GREATEST(1.00, COALESCE(t.expected_return_pct, t.upward_projection_pct, t.backtest_avg_trade_return_pct, 1.00))) AS target_profit_pct,
      CASE
        WHEN COALESCE(t.expected_return_pct, t.upward_projection_pct, 0) BETWEEN 1.00 AND 3.00 THEN 'IN_BAND'
        WHEN COALESCE(t.expected_return_pct, t.upward_projection_pct, 0) > 3.00 THEN 'ABOVE_BAND'
        ELSE 'NEAR_BAND'
      END AS target_band_status,
      (
        100
        - ABS(LEAST(3.00, GREATEST(1.00, COALESCE(t.expected_return_pct, t.upward_projection_pct, 1.00))) - 2.00) * 14
        + COALESCE(t.upward_probability_pct, 0) * 0.28
        - COALESCE(t.downward_probability_pct, 50) * 0.30
        + LEAST(COALESCE(t.risk_reward_ratio, 0), 8) * 3
        + COALESCE(t.projection_confidence_score, 0) * 0.35
        - GREATEST(COALESCE(t.expected_return_pct, 0) - 3.00, 0) * 6
        + CASE COALESCE(n.swing_news_signal, 'NO_RECENT_NEWS')
            WHEN 'BULLISH_CATALYST' THEN 6
            WHEN 'BEARISH_CATALYST' THEN -8
            WHEN 'NEWS_RISK_AVOID' THEN -20
            ELSE 0
          END
        + LEAST(6, GREATEST(-6, COALESCE(n.news_sentiment_score, 0) * 0.08))
        - LEAST(18, COALESCE(n.news_risk_score, 0) * 0.20)
      ) AS target_score
    FROM `jstockdata_reco_trade` t
    JOIN `jstockdata_scrips` s
      ON s.`Scrip` = t.scrip
     AND UPPER(TRIM(COALESCE(s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(s.`RecoUniverseRank`, 999999) <= 1000
    LEFT JOIN `jstockdata_reco_news_signal` n ON n.scrip = t.scrip
    WHERE t.assetclass = 'ETF'
      AND t.trade_signal = 'BUY'
      AND COALESCE(t.expected_return_pct, t.upward_projection_pct, t.backtest_avg_trade_return_pct, 0) >= 0.75
      AND COALESCE(t.upward_probability_pct, 0) >= 65
      AND COALESCE(t.downward_probability_pct, 100) <= 35
      AND COALESCE(t.risk_reward_ratio, 0) >= 1.20
      AND COALESCE(t.projection_confidence_score, 0) >= 40
      AND COALESCE(t.backtest_worst_trade_pct, -99) >= -8
    ORDER BY target_score DESC, FIELD(t.frequency, 'DAILY', 'WEEKLY'), t.`rank`, t.scrip
    LIMIT 10
  ) ranked
  CROSS JOIN (SELECT @etf_rank := 0) vars;

  INSERT INTO `jstockdata_reco_weekly_target_recos` (
    generated_at, reco_category, account_scope, target_rank, scrip, assetclass,
    source_table, direction, option_trade, option_type, option_side, strike_price,
    exp_date, dte, premium, premium_roi_pct, current_price, target_profit_pct,
    weeklyized_target_profit_pct,
    stop_review_pct, expected_return_pct, upward_projection_pct, upward_probability_pct,
    downward_projection_pct, downward_probability_pct, projection_confidence_score,
    recommendation_score, news_swing_signal, news_options_signal,
    news_sentiment_score, news_catalyst_score, news_risk_score,
    news_top_headline, news_top_url, target_band_status, notes
  )
  SELECT
    v_generated_at, 'OPTIONS', 'Non-Agentic Manual Only', @opt_rank := @opt_rank + 1,
    ranked.scrip, ranked.assetclass, 'jstockdata_reco_options', ranked.direction,
    ranked.option_trade, ranked.option_type, ranked.option_side, ranked.strike_price,
    ranked.exp_date, ranked.dte, ranked.premium, ranked.premium_roi_pct,
    ranked.close_price, ranked.premium_roi_pct, ranked.weeklyized_premium_roi_pct, -2.00,
    ranked.expected_underlying_move_pct, ranked.underlying_upward_projection_pct,
    ranked.underlying_upward_probability_pct, ranked.underlying_downward_projection_pct,
    ranked.underlying_downward_probability_pct, ranked.underlying_projection_confidence_score,
    ranked.target_score, ranked.swing_news_signal, ranked.options_news_signal,
    ranked.news_sentiment_score, ranked.catalyst_score, ranked.news_risk_score,
    ranked.top_headline, ranked.top_url, ranked.target_band_status,
    CONCAT('Manual non-Agentic options screen for 1%-3% weeklyized premium ROI. ',
           ranked.target_band_status,
           '; news=', ranked.options_news_signal,
           '; use covered calls or cash-secured puts only; verify option chain liquidity before order.')
  FROM (
    SELECT
      o.*,
      COALESCE(n.swing_news_signal, 'NO_RECENT_NEWS') AS swing_news_signal,
      COALESCE(n.options_news_signal, 'NO_RECENT_NEWS') AS options_news_signal,
      COALESCE(n.news_sentiment_score, 0) AS news_sentiment_score,
      COALESCE(n.catalyst_score, 0) AS catalyst_score,
      COALESCE(n.news_risk_score, 0) AS news_risk_score,
      n.top_headline,
      n.top_url,
      ROUND(o.premium_roi_pct * 7 / NULLIF(o.dte, 0), 2) AS weeklyized_premium_roi_pct,
      CASE
        WHEN ROUND(o.premium_roi_pct * 7 / NULLIF(o.dte, 0), 2) BETWEEN 1.00 AND 3.00 THEN 'IN_BAND'
        WHEN ROUND(o.premium_roi_pct * 7 / NULLIF(o.dte, 0), 2) BETWEEN 0.50 AND 0.99 THEN 'NEAR_BAND'
        ELSE 'BELOW_BAND'
      END AS target_band_status,
      (
        100
        - ABS(ROUND(o.premium_roi_pct * 7 / NULLIF(o.dte, 0), 2) - 2.00) * 15
        + COALESCE(o.probability_pct, 0) * 0.35
        + COALESCE(o.recommendation_score, 0) * 0.25
        + COALESCE(o.underlying_projection_confidence_score, 30) * 0.10
        + CASE
            WHEN o.option_trade = 'SELL PUT' AND COALESCE(n.options_news_signal, 'NO_RECENT_NEWS') = 'SUPPORTS_SELL_PUT' THEN 8
            WHEN o.option_trade = 'SELL CALL' AND COALESCE(n.options_news_signal, 'NO_RECENT_NEWS') = 'SUPPORTS_SELL_CALL' THEN 8
            WHEN COALESCE(n.options_news_signal, 'NO_RECENT_NEWS') IN ('AVOID_SHORT_PREMIUM_EVENT', 'AVOID_OPTIONS_NEWS_RISK') THEN -30
            ELSE 0
          END
        - LEAST(20, COALESCE(n.news_risk_score, 0) * 0.25)
      ) AS target_score
    FROM `jstockdata_reco_options` o
    JOIN `jstockdata_scrips` s
      ON s.`Scrip` = o.scrip
     AND UPPER(TRIM(COALESCE(s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(s.`RecoUniverseRank`, 999999) <= 1000
    LEFT JOIN `jstockdata_reco_news_signal` n ON n.scrip = o.scrip
    WHERE o.option_side = 'SELL'
      AND o.option_trade IN ('SELL PUT', 'SELL CALL')
      AND o.premium_roi_pct > 0
      AND ROUND(o.premium_roi_pct * 7 / NULLIF(o.dte, 0), 2) >= 0.50
      AND COALESCE(o.probability_pct, 0) >= 70
      AND COALESCE(o.recommendation_score, 0) >= 70
      AND COALESCE(o.dte, 999) BETWEEN 5 AND 60
      AND o.premium IS NOT NULL
      AND o.strike_price IS NOT NULL
      AND COALESCE(n.options_news_signal, 'NO_RECENT_NEWS') NOT IN ('AVOID_SHORT_PREMIUM_EVENT', 'AVOID_OPTIONS_NEWS_RISK')
    ORDER BY FIELD(target_band_status, 'IN_BAND', 'NEAR_BAND', 'BELOW_BAND'),
             target_score DESC, o.probability_pct DESC, o.premium_roi_pct DESC, o.scrip
    LIMIT 20
  ) ranked
  CROSS JOIN (SELECT @opt_rank := 0) vars;

  CALL reco_runlog_mark('reco_weekly_target_refresh', 'SUCCESS',
                        CONCAT('Generated weekly 1%-3% target rows at ', v_generated_at));
END$$
DELIMITER ;
