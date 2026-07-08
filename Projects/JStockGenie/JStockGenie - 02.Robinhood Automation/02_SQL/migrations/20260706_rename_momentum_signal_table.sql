-- Rename momentum output into the reco_* table namespace.
-- Run once after 20260705_momentum_signal.sql if the old table already exists.

SET @old_momentum_table_exists := (
  SELECT COUNT(*)
  FROM information_schema.tables
  WHERE table_schema = DATABASE()
    AND table_name = 'jstockdata_momentum_signal'
);

SET @new_momentum_table_exists := (
  SELECT COUNT(*)
  FROM information_schema.tables
  WHERE table_schema = DATABASE()
    AND table_name = 'jstockdata_reco_momentum_signal'
);

SET @rename_momentum_sql := CASE
  WHEN @old_momentum_table_exists = 1 AND @new_momentum_table_exists = 0
    THEN 'RENAME TABLE `jstockdata_momentum_signal` TO `jstockdata_reco_momentum_signal`'
  WHEN @old_momentum_table_exists = 0 AND @new_momentum_table_exists = 1
    THEN 'DO 0'
  ELSE 'SIGNAL SQLSTATE ''45000'' SET MESSAGE_TEXT = ''Unexpected momentum table rename state'''
END;

PREPARE rename_momentum_stmt FROM @rename_momentum_sql;
EXECUTE rename_momentum_stmt;
DEALLOCATE PREPARE rename_momentum_stmt;
