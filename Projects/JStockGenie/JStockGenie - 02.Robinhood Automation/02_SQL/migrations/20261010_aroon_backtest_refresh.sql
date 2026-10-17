-- Creates and refreshes the long-only Aroon backtest result table.
-- Install this procedure before deploying the matching reco_weekly_master_refresh.sql.

create definer = admin@`%` procedure reco_aroon_backtest_refresh()
BEGIN
  DECLARE v_started_at datetime DEFAULT NOW();
  DECLARE v_current_step varchar(128) DEFAULT 'reco_aroon_backtest_refresh';

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    CALL reco_runlog_mark(v_current_step, 'FAILED', 'Failed during reco_aroon_backtest_refresh');
    RESIGNAL;
  END;

  CREATE TABLE IF NOT EXISTS `jstockdata_aroon_backtest` (
    `frequency` varchar(20) NOT NULL,
    `scrip` varchar(20) NOT NULL,
    `assetclass` varchar(40) NULL,
    `rank` int NULL,
    `start_date` int NULL,
    `end_date` int NULL,
    `bars` int NOT NULL,
    `strategy_return_pct` decimal(18,4) NOT NULL,
    `buy_hold_return_pct` decimal(18,4) NOT NULL,
    `trades` int NOT NULL,
    `winning_trades` int NOT NULL,
    `win_rate_pct` decimal(18,4) NOT NULL,
    `time_in_market_pct` decimal(18,4) NOT NULL,
    `latest_signal` varchar(10) NULL,
    `signal_date` int NULL,
    `signal_change_date` int NULL,
    `close_price` decimal(18,4) NULL,
    `aroon_up` decimal(8,2) NULL,
    `aroon_down` decimal(8,2) NULL,
    `refreshed_at` datetime NOT NULL,
    PRIMARY KEY (`frequency`, `scrip`),
    KEY `ix_aroon_backtest_asset_rank` (`frequency`, `assetclass`, `rank`),
    KEY `ix_aroon_backtest_signal` (`frequency`, `latest_signal`, `signal_date`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

  TRUNCATE TABLE `jstockdata_aroon_backtest`;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_bars`;
  CREATE TEMPORARY TABLE `tmp_aroon_bars` ENGINE=InnoDB AS
  SELECT DISTINCT
    e.`SCRIP` AS scrip,
    TRIM(REPLACE(e.`FREQUENCY`, CHAR(13), '')) AS frequency,
    e.`DATE` AS trade_date,
    h.`CLOSE` AS close_price,
    UPPER(TRIM(REPLACE(COALESCE(e.`Aroon_Signal`, ''), CHAR(13), ''))) AS aroon_signal,
    e.`Aroon_Up` AS aroon_up,
    e.`Aroon_Down` AS aroon_down
  FROM `jstockdata_hatrend_extend` e
  JOIN `jstockdata_hatrend` h
    ON h.`SCRIP` = e.`SCRIP`
   AND TRIM(REPLACE(h.`FREQUENCY`, CHAR(13), '')) = TRIM(REPLACE(e.`FREQUENCY`, CHAR(13), ''))
   AND h.`DATE` = e.`DATE`
  WHERE TRIM(REPLACE(e.`FREQUENCY`, CHAR(13), '')) IN ('DAILY', 'WEEKLY', 'MONTHLY', 'QUARTERLY')
    AND h.`CLOSE` > 0;

  ALTER TABLE `tmp_aroon_bars`
    ADD PRIMARY KEY (`scrip`, `frequency`, `trade_date`),
    ADD KEY `ix_aroon_bars_frequency_date` (`frequency`, `trade_date`);

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_bars_lag`;
  CREATE TEMPORARY TABLE `tmp_aroon_bars_lag` ENGINE=InnoDB AS
  SELECT b.*,
    LAG(b.`aroon_signal`) OVER (PARTITION BY b.`scrip`, b.`frequency` ORDER BY b.`trade_date`) AS previous_signal
  FROM `tmp_aroon_bars` b;

  ALTER TABLE `tmp_aroon_bars_lag` ADD KEY `ix_aroon_bars_lag` (`scrip`, `frequency`, `trade_date`);

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_last_bar`;
  CREATE TEMPORARY TABLE `tmp_aroon_last_bar` ENGINE=InnoDB AS
  SELECT q.scrip, q.frequency, q.trade_date, q.close_price
  FROM (
    SELECT b.*, ROW_NUMBER() OVER (
      PARTITION BY b.scrip, b.frequency ORDER BY b.trade_date DESC
    ) AS latest_row
    FROM `tmp_aroon_bars` b
  ) q
  WHERE q.latest_row = 1;

  ALTER TABLE `tmp_aroon_last_bar` ADD PRIMARY KEY (`scrip`, `frequency`);

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_events`;
  CREATE TEMPORARY TABLE `tmp_aroon_events` ENGINE=InnoDB AS
  SELECT x.scrip, x.frequency, x.trade_date, x.close_price,
    x.aroon_signal AS trade_signal,
    ROW_NUMBER() OVER (PARTITION BY x.scrip, x.frequency ORDER BY x.trade_date) AS event_seq
  FROM `tmp_aroon_bars_lag` x
  WHERE x.aroon_signal IN ('BUY', 'SELL')
    AND COALESCE(x.previous_signal, '') <> x.aroon_signal;

  ALTER TABLE `tmp_aroon_events` ADD KEY `ix_aroon_events` (`scrip`, `frequency`, `event_seq`);

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_event_pairs`;
  CREATE TEMPORARY TABLE `tmp_aroon_event_pairs` ENGINE=InnoDB AS
  SELECT e.scrip, e.frequency, e.trade_date AS entry_date,
    e.close_price AS entry_price, e.trade_signal,
    COALESCE(LEAD(e.trade_signal) OVER (PARTITION BY e.scrip, e.frequency ORDER BY e.event_seq), 'SELL') AS next_signal,
    COALESCE(LEAD(e.trade_date) OVER (PARTITION BY e.scrip, e.frequency ORDER BY e.event_seq), last_bar.trade_date) AS next_date,
    COALESCE(LEAD(e.close_price) OVER (PARTITION BY e.scrip, e.frequency ORDER BY e.event_seq), last_bar.close_price) AS next_price
  FROM `tmp_aroon_events` e
  JOIN `tmp_aroon_last_bar` last_bar ON last_bar.scrip = e.scrip AND last_bar.frequency = e.frequency;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_trades`;
  CREATE TEMPORARY TABLE `tmp_aroon_trades` ENGINE=InnoDB AS
  SELECT p.scrip, p.frequency, p.entry_date, p.next_date AS exit_date,
    p.entry_price, p.next_price AS exit_price,
    p.next_price / p.entry_price AS return_ratio,
    (p.next_price / p.entry_price - 1) * 100 AS return_pct
  FROM `tmp_aroon_event_pairs` p
  WHERE p.trade_signal = 'BUY' AND p.next_signal = 'SELL'
    AND p.entry_price > 0 AND p.next_price > 0;

  ALTER TABLE `tmp_aroon_trades` ADD KEY `ix_aroon_trades` (`scrip`, `frequency`, `entry_date`, `exit_date`);

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_trade_metrics`;
  CREATE TEMPORARY TABLE `tmp_aroon_trade_metrics` ENGINE=InnoDB AS
  SELECT t.scrip, t.frequency, COUNT(*) AS trades,
    SUM(t.return_pct > 0) AS winning_trades,
    SUM(t.return_pct > 0) * 100.0 / COUNT(*) AS win_rate_pct,
    (EXP(SUM(LOG(t.return_ratio))) - 1) * 100 AS strategy_return_pct
  FROM `tmp_aroon_trades` t
  GROUP BY t.scrip, t.frequency;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_time`;
  CREATE TEMPORARY TABLE `tmp_aroon_time` ENGINE=InnoDB AS
  SELECT t.scrip, t.frequency, COUNT(b.trade_date) AS invested_bars
  FROM `tmp_aroon_trades` t
  JOIN `tmp_aroon_bars` b
    ON b.scrip = t.scrip AND b.frequency = t.frequency
   AND b.trade_date >= t.entry_date AND b.trade_date <= t.exit_date
  GROUP BY t.scrip, t.frequency;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_bar_summary`;
  CREATE TEMPORARY TABLE `tmp_aroon_bar_summary` ENGINE=InnoDB AS
  SELECT q.scrip, q.frequency, MIN(q.trade_date) AS start_date,
    MAX(q.trade_date) AS end_date, COUNT(*) AS bars,
    MAX(q.first_close_price) AS first_close_price,
    MAX(q.last_close_price) AS last_close_price
  FROM (
    SELECT b.*,
      FIRST_VALUE(b.close_price) OVER (
        PARTITION BY b.scrip, b.frequency ORDER BY b.trade_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
      ) AS first_close_price,
      LAST_VALUE(b.close_price) OVER (
        PARTITION BY b.scrip, b.frequency ORDER BY b.trade_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
      ) AS last_close_price
    FROM `tmp_aroon_bars` b
  ) q
  GROUP BY q.scrip, q.frequency;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_latest`;
  CREATE TEMPORARY TABLE `tmp_aroon_latest` ENGINE=InnoDB AS
  SELECT q.scrip, q.frequency, q.trade_date AS signal_date, q.close_price,
    q.aroon_signal AS latest_signal, q.aroon_up, q.aroon_down
  FROM (
    SELECT b.*, ROW_NUMBER() OVER (
      PARTITION BY b.scrip, b.frequency ORDER BY b.trade_date DESC
    ) AS latest_row
    FROM `tmp_aroon_bars` b
  ) q
  WHERE q.latest_row = 1;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_signal_change`;
  CREATE TEMPORARY TABLE `tmp_aroon_signal_change` ENGINE=InnoDB AS
  SELECT x.scrip, x.frequency, MAX(x.trade_date) AS signal_change_date
  FROM `tmp_aroon_bars_lag` x
  WHERE x.aroon_signal IN ('BUY', 'SELL') AND COALESCE(x.previous_signal, '') <> x.aroon_signal
  GROUP BY x.scrip, x.frequency;

  INSERT INTO `jstockdata_aroon_backtest` (
    `frequency`, `scrip`, `assetclass`, `rank`,
    `start_date`, `end_date`, `bars`, `strategy_return_pct`, `buy_hold_return_pct`,
    `trades`, `winning_trades`,
    `win_rate_pct`, `time_in_market_pct`, `latest_signal`, `signal_date`, `signal_change_date`,
    `close_price`, `aroon_up`, `aroon_down`, `refreshed_at`
  )
  SELECT b.frequency, b.scrip, UPPER(TRIM(s.`AssetClass`)), s.`Rank`,
    b.start_date, b.end_date, b.bars,
    COALESCE(m.strategy_return_pct, 0),
    (b.last_close_price / b.first_close_price - 1) * 100,
    COALESCE(m.trades, 0), COALESCE(m.winning_trades, 0),
    COALESCE(m.win_rate_pct, 0), COALESCE(t.invested_bars, 0) * 100.0 / b.bars,
    l.latest_signal, l.signal_date, c.signal_change_date, l.close_price, l.aroon_up, l.aroon_down,
    NOW()
  FROM `tmp_aroon_bar_summary` b
  LEFT JOIN `tmp_aroon_trade_metrics` m ON m.scrip = b.scrip AND m.frequency = b.frequency
  LEFT JOIN `tmp_aroon_time` t ON t.scrip = b.scrip AND t.frequency = b.frequency
  LEFT JOIN `tmp_aroon_latest` l ON l.scrip = b.scrip AND l.frequency = b.frequency
  LEFT JOIN `tmp_aroon_signal_change` c ON c.scrip = b.scrip AND c.frequency = b.frequency
  LEFT JOIN `jstockdata_scrips` s ON s.`Scrip` = b.scrip;

  CALL reco_runlog_mark(
    'reco_aroon_backtest_refresh', 'SUCCESS',
    CONCAT('Loaded ', ROW_COUNT(), ' Aroon backtest rows; started at ', v_started_at)
  );
END
