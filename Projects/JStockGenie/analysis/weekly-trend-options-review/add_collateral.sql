ALTER TABLE jstocksnp.jstockdata_option_recommendations
ADD COLUMN `Collateral` DECIMAL(16,4) GENERATED ALWAYS AS (
 CASE WHEN strategy='CASH_SECURED_PUT' THEN short_strike * contract_multiplier * contract_quantity
 ELSE ABS(short_strike-long_strike) * contract_multiplier * contract_quantity END
) STORED COMMENT 'USD gross collateral before premium: full strike cash for CSP; strike-width amount for spreads. Not broker-specific buying power.'
AFTER csp_cash_collateral_usd;
