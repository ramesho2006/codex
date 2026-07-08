-- Rename active reco output columns from symbol to scrip.
-- This script is safe to rerun after the columns have already been renamed.

SET @rename_sql := (
  SELECT IF(COUNT(*) = 1,
    'ALTER TABLE `jstockdata_backtest_summary` CHANGE COLUMN `symbol` `scrip` VARCHAR(20) NOT NULL',
    'DO 0')
  FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'jstockdata_backtest_summary' AND column_name = 'symbol'
);
PREPARE rename_stmt FROM @rename_sql; EXECUTE rename_stmt; DEALLOCATE PREPARE rename_stmt;

SET @rename_sql := (
  SELECT IF(COUNT(*) = 1,
    'ALTER TABLE `jstockdata_reco_backtest` CHANGE COLUMN `symbol` `scrip` VARCHAR(20) NOT NULL',
    'DO 0')
  FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'jstockdata_reco_backtest' AND column_name = 'symbol'
);
PREPARE rename_stmt FROM @rename_sql; EXECUTE rename_stmt; DEALLOCATE PREPARE rename_stmt;

SET @rename_sql := (
  SELECT IF(COUNT(*) = 1,
    'ALTER TABLE `jstockdata_reco_basket_actions` CHANGE COLUMN `symbol` `scrip` VARCHAR(20) NOT NULL',
    'DO 0')
  FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'jstockdata_reco_basket_actions' AND column_name = 'symbol'
);
PREPARE rename_stmt FROM @rename_sql; EXECUTE rename_stmt; DEALLOCATE PREPARE rename_stmt;

SET @rename_sql := (
  SELECT IF(COUNT(*) = 1,
    'ALTER TABLE `jstockdata_reco_basket_current` CHANGE COLUMN `symbol` `scrip` VARCHAR(20) NOT NULL',
    'DO 0')
  FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'jstockdata_reco_basket_current' AND column_name = 'symbol'
);
PREPARE rename_stmt FROM @rename_sql; EXECUTE rename_stmt; DEALLOCATE PREPARE rename_stmt;

SET @rename_sql := (
  SELECT IF(COUNT(*) = 1,
    'ALTER TABLE `jstockdata_reco_basket_history` CHANGE COLUMN `symbol` `scrip` VARCHAR(20) NOT NULL',
    'DO 0')
  FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'jstockdata_reco_basket_history' AND column_name = 'symbol'
);
PREPARE rename_stmt FROM @rename_sql; EXECUTE rename_stmt; DEALLOCATE PREPARE rename_stmt;

SET @rename_sql := (
  SELECT IF(COUNT(*) = 1,
    'ALTER TABLE `jstockdata_reco_basket_positions` CHANGE COLUMN `symbol` `scrip` VARCHAR(20) NOT NULL',
    'DO 0')
  FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'jstockdata_reco_basket_positions' AND column_name = 'symbol'
);
PREPARE rename_stmt FROM @rename_sql; EXECUTE rename_stmt; DEALLOCATE PREPARE rename_stmt;

SET @rename_sql := (
  SELECT IF(COUNT(*) = 1,
    'ALTER TABLE `jstockdata_reco_invest` CHANGE COLUMN `symbol` `scrip` VARCHAR(20) NOT NULL',
    'DO 0')
  FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'jstockdata_reco_invest' AND column_name = 'symbol'
);
PREPARE rename_stmt FROM @rename_sql; EXECUTE rename_stmt; DEALLOCATE PREPARE rename_stmt;

SET @rename_sql := (
  SELECT IF(COUNT(*) = 1,
    'ALTER TABLE `jstockdata_reco_momentum_signal` CHANGE COLUMN `symbol` `scrip` VARCHAR(20) NOT NULL',
    'DO 0')
  FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'jstockdata_reco_momentum_signal' AND column_name = 'symbol'
);
PREPARE rename_stmt FROM @rename_sql; EXECUTE rename_stmt; DEALLOCATE PREPARE rename_stmt;

SET @rename_sql := (
  SELECT IF(COUNT(*) = 1,
    'ALTER TABLE `jstockdata_reco_projection` CHANGE COLUMN `symbol` `scrip` VARCHAR(20) NOT NULL',
    'DO 0')
  FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'jstockdata_reco_projection' AND column_name = 'symbol'
);
PREPARE rename_stmt FROM @rename_sql; EXECUTE rename_stmt; DEALLOCATE PREPARE rename_stmt;

SET @rename_sql := (
  SELECT IF(COUNT(*) = 1,
    'ALTER TABLE `jstockdata_reco_trade` CHANGE COLUMN `symbol` `scrip` VARCHAR(20) NOT NULL',
    'DO 0')
  FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'jstockdata_reco_trade' AND column_name = 'symbol'
);
PREPARE rename_stmt FROM @rename_sql; EXECUTE rename_stmt; DEALLOCATE PREPARE rename_stmt;

SET @rename_sql := (
  SELECT IF(COUNT(*) = 1,
    'ALTER TABLE `jstockdata_reco_weekly_target_recos` CHANGE COLUMN `symbol` `scrip` VARCHAR(20) NOT NULL',
    'DO 0')
  FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'jstockdata_reco_weekly_target_recos' AND column_name = 'symbol'
);
PREPARE rename_stmt FROM @rename_sql; EXECUTE rename_stmt; DEALLOCATE PREPARE rename_stmt;

SET @rename_sql := (
  SELECT IF(COUNT(*) = 1,
    'ALTER TABLE `jstockdata_reco_weekly_target_recos` DROP INDEX `ix_weekly_target_symbol`, ADD KEY `ix_weekly_target_scrip` (`scrip`)',
    'DO 0')
  FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 'jstockdata_reco_weekly_target_recos' AND index_name = 'ix_weekly_target_symbol'
);
PREPARE rename_stmt FROM @rename_sql; EXECUTE rename_stmt; DEALLOCATE PREPARE rename_stmt;
