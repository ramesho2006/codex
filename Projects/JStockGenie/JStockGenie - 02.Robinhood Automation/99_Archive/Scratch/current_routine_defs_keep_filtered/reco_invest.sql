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

END