-- Review-only intraday monitor for leveraged ETF baskets.
-- Live quotes are written by 05_Tools/leveraged_dip_monitor.py.

CREATE TABLE IF NOT EXISTS jstockdata_reco_leveraged_dip_config (
    basket VARCHAR(50) NOT NULL,
    scrip VARCHAR(20) NOT NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    dip_level_1_pct DECIMAL(6,2) NOT NULL DEFAULT 2.00,
    dip_level_2_pct DECIMAL(6,2) NOT NULL DEFAULT 4.00,
    dip_level_3_pct DECIMAL(6,2) NOT NULL DEFAULT 6.00,
    add_level_1_capital_pct DECIMAL(6,2) NOT NULL DEFAULT 2.50,
    add_level_2_capital_pct DECIMAL(6,2) NOT NULL DEFAULT 3.00,
    add_level_3_capital_pct DECIMAL(6,2) NOT NULL DEFAULT 4.50,
    max_alerts_per_month INT NOT NULL DEFAULT 3,
    cooldown_minutes INT NOT NULL DEFAULT 180,
    cash_reserve_pct DECIMAL(6,2) NOT NULL DEFAULT 10.00,
    required_opti_direction VARCHAR(20) NOT NULL DEFAULT 'BULLISH',
    required_opti_last_signal VARCHAR(10) NOT NULL DEFAULT 'BUY',
    min_opti_strength_pct DECIMAL(6,2) NOT NULL DEFAULT 30.00,
    max_opti_days_since INT NOT NULL DEFAULT 180,
    review_only TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (basket, scrip)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS jstockdata_live_quote_snapshot (
    quote_id BIGINT NOT NULL AUTO_INCREMENT,
    observed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    quote_at_utc DATETIME NULL,
    provider VARCHAR(30) NOT NULL,
    market_state VARCHAR(20) NULL,
    scrip VARCHAR(20) NOT NULL,
    live_price DECIMAL(18,6) NOT NULL,
    provider_previous_close DECIMAL(18,6) NULL,
    PRIMARY KEY (quote_id),
    UNIQUE KEY uq_live_quote_provider_scrip_time (provider, scrip, quote_at_utc),
    KEY idx_live_quote_scrip_observed (scrip, observed_at)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS jstockdata_reco_leveraged_dip_monitor_log (
    monitor_log_id BIGINT NOT NULL AUTO_INCREMENT,
    observed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    basket VARCHAR(50) NOT NULL,
    scrip VARCHAR(20) NOT NULL,
    quote_at_utc DATETIME NULL,
    market_state VARCHAR(20) NULL,
    eod_date INT NULL,
    eod_close DECIMAL(18,6) NULL,
    live_price DECIMAL(18,6) NULL,
    change_from_eod_pct DECIMAL(10,4) NULL,
    sma_delta_trend VARCHAR(10) NULL,
    lo_delta_signal VARCHAR(10) NULL,
    combined_signal VARCHAR(10) NULL,
    opti_last_signal VARCHAR(10) NULL,
    opti_chance_pct DECIMAL(10,2) NULL,
    opti_direction VARCHAR(20) NULL,
    opti_direction_pct DECIMAL(10,2) NULL,
    opti_strength_pct DECIMAL(10,2) NULL,
    opti_days_since INT NULL,
    opti_price_change_pct DECIMAL(10,2) NULL,
    trigger_level INT NOT NULL DEFAULT 0,
    suggested_add_capital_pct DECIMAL(6,2) NOT NULL DEFAULT 0.00,
    action_status VARCHAR(40) NOT NULL,
    reason VARCHAR(500) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (monitor_log_id),
    KEY idx_leveraged_monitor_basket_time (basket, observed_at),
    KEY idx_leveraged_monitor_scrip_time (scrip, observed_at),
    KEY idx_leveraged_monitor_action (action_status, observed_at)
) ENGINE=InnoDB;

INSERT INTO jstockdata_reco_leveraged_dip_config (basket, scrip)
SELECT b.Basket, b.scrip
FROM jstockdata_basket b
WHERE b.Basket = 'SNP-ETF-LEVG'
ON DUPLICATE KEY UPDATE updated_at = updated_at;
