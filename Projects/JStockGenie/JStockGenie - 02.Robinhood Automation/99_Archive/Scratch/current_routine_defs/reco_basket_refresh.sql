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
END