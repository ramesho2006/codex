-- Add a weekly recommendation universe flag to jstockdata_scrips.
-- Values:
--   KEEP = included in the active recommendation universe
--   OMIT = excluded from the active recommendation universe

SET @column_exists := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'jstockdata_scrips'
    AND COLUMN_NAME = 'RecoUniverseStatus'
);

SET @ddl := IF(
  @column_exists = 0,
  'ALTER TABLE jstockdata_scrips ADD COLUMN RecoUniverseStatus VARCHAR(10) DEFAULT ''OMIT''',
  'SELECT ''RecoUniverseStatus already exists'' AS migration_note'
);
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @column_exists := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'jstockdata_scrips'
    AND COLUMN_NAME = 'RecoUniverseRank'
);

SET @ddl := IF(
  @column_exists = 0,
  'ALTER TABLE jstockdata_scrips ADD COLUMN RecoUniverseRank INT NULL',
  'SELECT ''RecoUniverseRank already exists'' AS migration_note'
);
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @index_exists := (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'jstockdata_scrips'
    AND INDEX_NAME = 'ix_jstockdata_scrips_reco_universe_status'
);

SET @ddl := IF(
  @index_exists = 0,
  'CREATE INDEX ix_jstockdata_scrips_reco_universe_status ON jstockdata_scrips (RecoUniverseStatus, AssetClass, Scrip)',
  'SELECT ''ix_jstockdata_scrips_reco_universe_status already exists'' AS migration_note'
);
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @index_exists := (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'jstockdata_scrips'
    AND INDEX_NAME = 'ix_jstockdata_scrips_reco_universe_rank'
);

SET @ddl := IF(
  @index_exists = 0,
  'CREATE INDEX ix_jstockdata_scrips_reco_universe_rank ON jstockdata_scrips (RecoUniverseStatus, RecoUniverseRank, AssetClass, Scrip)',
  'SELECT ''ix_jstockdata_scrips_reco_universe_rank already exists'' AS migration_note'
);
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
