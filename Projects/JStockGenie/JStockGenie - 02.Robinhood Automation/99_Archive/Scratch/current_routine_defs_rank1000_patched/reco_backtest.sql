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
END