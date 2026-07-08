-- Add lightweight indexes used by reco routines that join current/recent trend rows.
-- Safe to rerun; each ALTER only runs when the index is missing.

SET @idx_sql := (
  SELECT IF(COUNT(*) = 0,
    'ALTER TABLE `jstockdata_harecent` ADD INDEX `ix_harecent_scrip_freq_date` (`SCRIP`, `Frequency`, `DATE`)',
    'DO 0')
  FROM information_schema.statistics
  WHERE table_schema = DATABASE()
    AND table_name = 'jstockdata_harecent'
    AND index_name = 'ix_harecent_scrip_freq_date'
);
PREPARE idx_stmt FROM @idx_sql; EXECUTE idx_stmt; DEALLOCATE PREPARE idx_stmt;

SET @idx_sql := (
  SELECT IF(COUNT(*) = 0,
    'ALTER TABLE `jstockdata_harecent_extend` ADD INDEX `ix_harecent_ext_scrip_freq_date` (`SCRIP`, `FREQUENCY`, `DATE`)',
    'DO 0')
  FROM information_schema.statistics
  WHERE table_schema = DATABASE()
    AND table_name = 'jstockdata_harecent_extend'
    AND index_name = 'ix_harecent_ext_scrip_freq_date'
);
PREPARE idx_stmt FROM @idx_sql; EXECUTE idx_stmt; DEALLOCATE PREPARE idx_stmt;
