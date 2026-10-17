create definer = admin@`%` procedure reco_aroon_backtest_additional_refresh()
BEGIN
  DECLARE v_started_at datetime DEFAULT NOW();
  DECLARE v_current_step varchar(128) DEFAULT 'reco_aroon_backtest_additional_refresh';

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    CALL reco_runlog_mark(v_current_step, 'FAILED', 'Failed during reco_aroon_backtest_additional_refresh');
    RESIGNAL;
  END;

  CREATE TABLE IF NOT EXISTS `jstockdata_aroon_backtest_additional` (
    `frequency` varchar(20) NOT NULL,
    `scrip` varchar(20) NOT NULL,
    `assetclass` varchar(40) NULL,
    `rank` int NULL,
    `start_date` int NULL,
    `end_date` int NULL,
    `bars` int NOT NULL,
    `strategy_return_pct` decimal(18,4) NOT NULL,
    `buy_hold_return_pct` decimal(18,4) NOT NULL,
    `trade_suitability` varchar(20) NOT NULL,
    `trades` int NOT NULL,
    `winning_trades` int NOT NULL,
    `win_rate_pct` decimal(18,4) NOT NULL,
    `time_in_market_pct` decimal(18,4) NOT NULL,
    `total_buy_qty` int NOT NULL,
    `additional_buy_qty` int NOT NULL,
    `max_position_qty` int NOT NULL,
    `weighted_avg_buy_cost` decimal(18,4) NULL,
    `last_cycle_buy_qty` int NULL,
    `last_cycle_avg_cost` decimal(18,4) NULL,
    `last_cycle_sell_price` decimal(18,4) NULL,
    `last_cycle_return_pct` decimal(18,4) NULL,
    `last_cycle_forced_exit` char(1) NOT NULL,
    `latest_signal` varchar(10) NULL,
    `signal_date` int NULL,
    `signal_change_date` int NULL,
    `close_price` decimal(18,4) NULL,
    `aroon_up` decimal(8,2) NULL,
    `aroon_down` decimal(8,2) NULL,
    `refreshed_at` datetime NOT NULL,
    PRIMARY KEY (`frequency`, `scrip`),
    KEY `ix_aroon_additional_asset_rank` (`frequency`, `assetclass`, `rank`),
    KEY `ix_aroon_additional_signal` (`frequency`, `latest_signal`, `signal_date`),
    KEY `ix_aroon_additional_suitability` (`frequency`, `trade_suitability`),
    KEY `ix_aroon_additional_position` (`frequency`, `max_position_qty`, `last_cycle_return_pct`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

  TRUNCATE TABLE `jstockdata_aroon_backtest_additional`;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_additional_bars`;
  CREATE TEMPORARY TABLE `tmp_aroon_additional_bars` ENGINE=InnoDB AS
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

  ALTER TABLE `tmp_aroon_additional_bars`
    ADD PRIMARY KEY (`scrip`, `frequency`, `trade_date`),
    ADD KEY `ix_aroon_additional_bars_date` (`frequency`, `trade_date`);

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_additional_history`;
  CREATE TEMPORARY TABLE `tmp_aroon_additional_history` ENGINE=InnoDB AS
  SELECT
    b.*,
    LAG(b.`aroon_down`) OVER (
      PARTITION BY b.`scrip`, b.`frequency` ORDER BY b.`trade_date`
    ) AS previous_aroon_down,
    LAG(b.`aroon_up`) OVER (
      PARTITION BY b.`scrip`, b.`frequency` ORDER BY b.`trade_date`
    ) AS previous_aroon_up
  FROM `tmp_aroon_additional_bars` b;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_additional_conditions`;
  CREATE TEMPORARY TABLE `tmp_aroon_additional_conditions` ENGINE=InnoDB AS
  SELECT
    h.*,
    CASE WHEN ROUND(h.previous_aroon_down, 2) = 100.00
           AND ROUND(h.aroon_down, 2) = 92.86 THEN 1 ELSE 0 END AS is_buy_condition,
    CASE WHEN ROUND(h.previous_aroon_up, 2) = 100.00
           AND ROUND(h.aroon_up, 2) = 92.86 THEN 1 ELSE 0 END AS is_sell_condition
  FROM `tmp_aroon_additional_history` h;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_additional_sequence`;
  CREATE TEMPORARY TABLE `tmp_aroon_additional_sequence` ENGINE=InnoDB AS
  SELECT
    c.*,
    COALESCE(SUM(c.is_sell_condition) OVER (
      PARTITION BY c.scrip, c.frequency ORDER BY c.trade_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ), 0) AS sell_seq_before,
    SUM(c.is_sell_condition) OVER (
      PARTITION BY c.scrip, c.frequency ORDER BY c.trade_date
      ROWS UNBOUNDED PRECEDING
    ) AS sell_seq_after
  FROM `tmp_aroon_additional_conditions` c;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_additional_last_bar`;
  CREATE TEMPORARY TABLE `tmp_aroon_additional_last_bar` ENGINE=InnoDB AS
  SELECT q.scrip, q.frequency, q.trade_date, q.close_price
  FROM (
    SELECT b.*,
      ROW_NUMBER() OVER (
        PARTITION BY b.scrip, b.frequency ORDER BY b.trade_date DESC
      ) AS latest_row
    FROM `tmp_aroon_additional_bars` b
  ) q
  WHERE q.latest_row = 1;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_additional_buy_cycles`;
  CREATE TEMPORARY TABLE `tmp_aroon_additional_buy_cycles` ENGINE=InnoDB AS
  SELECT
    scrip,
    frequency,
    sell_seq_before AS cycle_id,
    MIN(trade_date) AS first_buy_date,
    COUNT(*) AS buy_qty,
    SUM(close_price) AS total_buy_cost,
    AVG(close_price) AS average_buy_cost
  FROM `tmp_aroon_additional_sequence`
  WHERE is_buy_condition = 1
    AND is_sell_condition = 0
  GROUP BY scrip, frequency, sell_seq_before;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_additional_sell_events`;
  CREATE TEMPORARY TABLE `tmp_aroon_additional_sell_events` ENGINE=InnoDB AS
  SELECT
    scrip,
    frequency,
    sell_seq_after AS cycle_id,
    trade_date AS sell_date,
    close_price AS sell_price
  FROM `tmp_aroon_additional_sequence`
  WHERE is_sell_condition = 1;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_additional_cycles`;
  CREATE TEMPORARY TABLE `tmp_aroon_additional_cycles` ENGINE=InnoDB AS
  SELECT
    b.scrip,
    b.frequency,
    b.cycle_id,
    b.first_buy_date,
    COALESCE(s.sell_date, l.trade_date) AS exit_date,
    b.buy_qty,
    b.total_buy_cost,
    b.average_buy_cost,
    COALESCE(s.sell_price, l.close_price) AS sell_price,
    COALESCE(s.sell_price, l.close_price) * b.buy_qty / b.total_buy_cost AS return_ratio,
    (COALESCE(s.sell_price, l.close_price) * b.buy_qty / b.total_buy_cost - 1) * 100 AS return_pct,
    CASE WHEN s.sell_date IS NULL THEN 'Y' ELSE 'N' END AS forced_exit
  FROM `tmp_aroon_additional_buy_cycles` b
  JOIN `tmp_aroon_additional_last_bar` l
    ON l.scrip = b.scrip AND l.frequency = b.frequency
  LEFT JOIN `tmp_aroon_additional_sell_events` s
    ON s.scrip = b.scrip
   AND s.frequency = b.frequency
   AND s.cycle_id = b.cycle_id + 1;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_additional_cycle_ranked`;
  CREATE TEMPORARY TABLE `tmp_aroon_additional_cycle_ranked` ENGINE=InnoDB AS
  SELECT
    c.*,
    ROW_NUMBER() OVER (
      PARTITION BY c.scrip, c.frequency ORDER BY c.cycle_id DESC
    ) AS last_cycle_row
  FROM `tmp_aroon_additional_cycles` c;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_additional_time`;
  CREATE TEMPORARY TABLE `tmp_aroon_additional_time` ENGINE=InnoDB AS
  SELECT
    c.scrip,
    c.frequency,
    COUNT(b.trade_date) AS invested_bars
  FROM `tmp_aroon_additional_cycles` c
  JOIN `tmp_aroon_additional_bars` b
    ON b.scrip = c.scrip
   AND b.frequency = c.frequency
   AND b.trade_date >= c.first_buy_date
   AND b.trade_date <= c.exit_date
  GROUP BY c.scrip, c.frequency;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_additional_metrics`;
  CREATE TEMPORARY TABLE `tmp_aroon_additional_metrics` ENGINE=InnoDB AS
  SELECT
    c.scrip,
    c.frequency,
    COUNT(*) AS trades,
    SUM(c.return_pct > 0) AS winning_trades,
    SUM(c.return_pct > 0) * 100.0 / COUNT(*) AS win_rate_pct,
    (EXP(SUM(LOG(c.return_ratio))) - 1) * 100 AS strategy_return_pct,
    SUM(c.buy_qty) AS total_buy_qty,
    SUM(c.buy_qty - 1) AS additional_buy_qty,
    MAX(c.buy_qty) AS max_position_qty,
    SUM(c.total_buy_cost) / SUM(c.buy_qty) AS weighted_avg_buy_cost,
    MAX(CASE WHEN c.last_cycle_row = 1 THEN c.buy_qty END) AS last_cycle_buy_qty,
    MAX(CASE WHEN c.last_cycle_row = 1 THEN c.average_buy_cost END) AS last_cycle_avg_cost,
    MAX(CASE WHEN c.last_cycle_row = 1 THEN c.sell_price END) AS last_cycle_sell_price,
    MAX(CASE WHEN c.last_cycle_row = 1 THEN c.return_pct END) AS last_cycle_return_pct,
    MAX(CASE WHEN c.last_cycle_row = 1 THEN c.forced_exit END) AS last_cycle_forced_exit
  FROM `tmp_aroon_additional_cycle_ranked` c
  GROUP BY c.scrip, c.frequency;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_additional_bar_summary`;
  CREATE TEMPORARY TABLE `tmp_aroon_additional_bar_summary` ENGINE=InnoDB AS
  SELECT
    q.scrip,
    q.frequency,
    MIN(q.trade_date) AS start_date,
    MAX(q.trade_date) AS end_date,
    COUNT(*) AS bars,
    MAX(q.first_close_price) AS first_close_price,
    MAX(q.last_close_price) AS last_close_price
  FROM (
    SELECT
      b.*,
      FIRST_VALUE(b.close_price) OVER (
        PARTITION BY b.scrip, b.frequency ORDER BY b.trade_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
      ) AS first_close_price,
      LAST_VALUE(b.close_price) OVER (
        PARTITION BY b.scrip, b.frequency ORDER BY b.trade_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
      ) AS last_close_price
    FROM `tmp_aroon_additional_bars` b
  ) q
  GROUP BY q.scrip, q.frequency;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_additional_latest`;
  CREATE TEMPORARY TABLE `tmp_aroon_additional_latest` ENGINE=InnoDB AS
  SELECT q.scrip, q.frequency, q.trade_date AS signal_date, q.close_price,
    q.aroon_signal AS latest_signal, q.aroon_up, q.aroon_down
  FROM (
    SELECT b.*, ROW_NUMBER() OVER (
      PARTITION BY b.scrip, b.frequency ORDER BY b.trade_date DESC
    ) AS latest_row
    FROM `tmp_aroon_additional_bars` b
  ) q
  WHERE q.latest_row = 1;

  DROP TEMPORARY TABLE IF EXISTS `tmp_aroon_additional_signal_change`;
  CREATE TEMPORARY TABLE `tmp_aroon_additional_signal_change` ENGINE=InnoDB AS
  SELECT scrip, frequency, MAX(trade_date) AS signal_change_date
  FROM `tmp_aroon_additional_sequence`
  WHERE is_buy_condition = 1 OR is_sell_condition = 1
  GROUP BY scrip, frequency;

  INSERT INTO `jstockdata_aroon_backtest_additional` (
    `frequency`, `scrip`, `assetclass`, `rank`, `start_date`, `end_date`, `bars`,
    `strategy_return_pct`, `buy_hold_return_pct`, `trade_suitability`, `trades`, `winning_trades`,
    `win_rate_pct`, `time_in_market_pct`, `total_buy_qty`, `additional_buy_qty`,
    `max_position_qty`, `weighted_avg_buy_cost`, `last_cycle_buy_qty`,
    `last_cycle_avg_cost`, `last_cycle_sell_price`, `last_cycle_return_pct`,
    `last_cycle_forced_exit`, `latest_signal`, `signal_date`, `signal_change_date`,
    `close_price`, `aroon_up`, `aroon_down`, `refreshed_at`
  )
  SELECT
    b.frequency,
    b.scrip,
    UPPER(TRIM(s.`AssetClass`)),
    s.`Rank`,
    b.start_date,
    b.end_date,
    b.bars,
    COALESCE(m.strategy_return_pct, 0),
    (b.last_close_price / b.first_close_price - 1) * 100,
    CASE
      WHEN COALESCE(m.strategy_return_pct, 0) > 0
       AND COALESCE(m.trades, 0) >= 3
       AND COALESCE(m.win_rate_pct, 0) >= 60
       AND (b.last_close_price / b.first_close_price - 1) * 100 > 0 THEN 'BOTH'
      WHEN COALESCE(m.strategy_return_pct, 0) > 0
       AND COALESCE(m.trades, 0) >= 3
       AND COALESCE(m.win_rate_pct, 0) >= 60 THEN 'SWING'
      WHEN (b.last_close_price / b.first_close_price - 1) * 100 > 0 THEN 'BUY_AND_HOLD'
      ELSE 'REVIEW'
    END,
    COALESCE(m.trades, 0),
    COALESCE(m.winning_trades, 0),
    COALESCE(m.win_rate_pct, 0),
    COALESCE(t.invested_bars, 0) * 100.0 / b.bars,
    COALESCE(m.total_buy_qty, 0),
    COALESCE(m.additional_buy_qty, 0),
    COALESCE(m.max_position_qty, 0),
    m.weighted_avg_buy_cost,
    m.last_cycle_buy_qty,
    m.last_cycle_avg_cost,
    m.last_cycle_sell_price,
    m.last_cycle_return_pct,
    COALESCE(m.last_cycle_forced_exit, 'N'),
    l.latest_signal,
    l.signal_date,
    c.signal_change_date,
    l.close_price,
    l.aroon_up,
    l.aroon_down,
    NOW()
  FROM `tmp_aroon_additional_bar_summary` b
  LEFT JOIN `tmp_aroon_additional_metrics` m
    ON m.scrip = b.scrip AND m.frequency = b.frequency
  LEFT JOIN `tmp_aroon_additional_time` t
    ON t.scrip = b.scrip AND t.frequency = b.frequency
  LEFT JOIN `tmp_aroon_additional_latest` l
    ON l.scrip = b.scrip AND l.frequency = b.frequency
  LEFT JOIN `tmp_aroon_additional_signal_change` c
    ON c.scrip = b.scrip AND c.frequency = b.frequency
  LEFT JOIN `jstockdata_scrips` s
    ON s.`Scrip` = b.scrip;

  CALL reco_runlog_mark(
    'reco_aroon_backtest_additional_refresh',
    'SUCCESS',
    CONCAT('Loaded ', ROW_COUNT(), ' additional-entry Aroon backtest rows; started at ', v_started_at)
  );
END
