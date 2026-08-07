-- Keep current position analysis date at the end of the table layout.

ALTER TABLE jstockdata_current_positions
  MODIFY COLUMN analysis_date DATE NULL AFTER loaded_at;
