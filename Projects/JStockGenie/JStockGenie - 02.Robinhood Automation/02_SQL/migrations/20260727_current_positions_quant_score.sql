-- Add the latest JStockGenie quant score to current position snapshots.

SET @add_current_position_quant_score := (
  SELECT IF(COUNT(*) = 0,
    'ALTER TABLE jstockdata_current_positions ADD COLUMN quant_score DECIMAL(10,4) NULL AFTER reco_action',
    'SELECT ''quant_score already exists'' AS migration_note')
  FROM information_schema.columns
  WHERE table_schema = DATABASE()
    AND table_name = 'jstockdata_current_positions'
    AND column_name = 'quant_score'
);

PREPARE stmt FROM @add_current_position_quant_score;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
