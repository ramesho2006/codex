CREATE TABLE IF NOT EXISTS jstockdata_fusion_run (
    run_id BIGINT NOT NULL AUTO_INCREMENT,
    run_name VARCHAR(120) NOT NULL,
    trend_build_date DATE NULL,
    analysis_date DATE NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'CREATED',
    source_note VARCHAR(500) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME NULL,
    PRIMARY KEY (run_id),
    KEY idx_fusion_run_analysis_date (analysis_date),
    KEY idx_fusion_run_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS jstockdata_fusion_base_universe (
    run_id BIGINT NOT NULL,
    scrip VARCHAR(20) NOT NULL,
    assetclass VARCHAR(30) NOT NULL,
    company_name VARCHAR(160) NULL,
    universe_rank INT NULL,
    reco_universe_status VARCHAR(20) NULL,
    reco_universe_rank INT NULL,
    is_current_position TINYINT(1) NOT NULL DEFAULT 0,
    is_optionable TINYINT(1) NULL,
    source_table VARCHAR(80) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (run_id, scrip, assetclass),
    KEY idx_fusion_base_scrip (scrip),
    KEY idx_fusion_base_assetclass (assetclass),
    KEY idx_fusion_base_position (run_id, is_current_position),
    CONSTRAINT fk_fusion_base_run
        FOREIGN KEY (run_id) REFERENCES jstockdata_fusion_run (run_id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS jstockdata_fusion_internal_signal (
    run_id BIGINT NOT NULL,
    scrip VARCHAR(20) NOT NULL,
    assetclass VARCHAR(30) NOT NULL,
    daily_combined_signal VARCHAR(80) NULL,
    weekly_combined_signal VARCHAR(80) NULL,
    daily_momentum VARCHAR(80) NULL,
    daily_confidence_pct DECIMAL(8,4) NULL,
    weekly_momentum VARCHAR(80) NULL,
    weekly_confidence_pct DECIMAL(8,4) NULL,
    weekly_verdict VARCHAR(120) NULL,
    direction VARCHAR(80) NULL,
    direction_confidence_pct DECIMAL(8,4) NULL,
    signal_date DATE NULL,
    notes VARCHAR(1000) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (run_id, scrip, assetclass),
    KEY idx_fusion_internal_scrip (scrip),
    KEY idx_fusion_internal_signal_date (signal_date),
    CONSTRAINT fk_fusion_internal_run
        FOREIGN KEY (run_id) REFERENCES jstockdata_fusion_run (run_id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS jstockdata_fusion_external_signal (
    external_signal_id BIGINT NOT NULL AUTO_INCREMENT,
    run_id BIGINT NOT NULL,
    scrip VARCHAR(20) NOT NULL,
    assetclass VARCHAR(30) NOT NULL,
    source_name VARCHAR(80) NOT NULL,
    signal_category VARCHAR(80) NOT NULL,
    signal_name VARCHAR(120) NOT NULL,
    signal_value VARCHAR(255) NULL,
    numeric_value DECIMAL(18,6) NULL,
    score DECIMAL(10,4) NULL,
    confidence_pct DECIMAL(8,4) NULL,
    timeframe VARCHAR(30) NULL,
    as_of_date DATE NULL,
    source_url VARCHAR(500) NULL,
    notes VARCHAR(1000) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (external_signal_id),
    KEY idx_fusion_external_run_scrip (run_id, scrip, assetclass),
    KEY idx_fusion_external_source (source_name, signal_category),
    KEY idx_fusion_external_timeframe (timeframe),
    CONSTRAINT fk_fusion_external_run
        FOREIGN KEY (run_id) REFERENCES jstockdata_fusion_run (run_id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS jstockdata_fusion_score (
    run_id BIGINT NOT NULL,
    scrip VARCHAR(20) NOT NULL,
    assetclass VARCHAR(30) NOT NULL,
    short_term_score DECIMAL(10,4) NULL,
    mid_term_score DECIMAL(10,4) NULL,
    long_term_score DECIMAL(10,4) NULL,
    sell_put_score DECIMAL(10,4) NULL,
    sell_call_score DECIMAL(10,4) NULL,
    investment_score DECIMAL(10,4) NULL,
    risk_score DECIMAL(10,4) NULL,
    fusion_score DECIMAL(10,4) NULL,
    confidence_pct DECIMAL(8,4) NULL,
    score_version VARCHAR(40) NOT NULL DEFAULT 'v1',
    notes VARCHAR(1000) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NULL,
    PRIMARY KEY (run_id, scrip, assetclass),
    KEY idx_fusion_score_scrip (scrip),
    KEY idx_fusion_score_final (run_id, fusion_score),
    CONSTRAINT fk_fusion_score_run
        FOREIGN KEY (run_id) REFERENCES jstockdata_fusion_run (run_id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS jstockdata_fusion_verdict (
    run_id BIGINT NOT NULL,
    scrip VARCHAR(20) NOT NULL,
    assetclass VARCHAR(30) NOT NULL,
    fusion_verdict VARCHAR(120) NULL,
    short_term_verdict VARCHAR(120) NULL,
    mid_term_verdict VARCHAR(120) NULL,
    long_term_verdict VARCHAR(120) NULL,
    sell_put_suitability VARCHAR(120) NULL,
    sell_call_suitability VARCHAR(120) NULL,
    direction VARCHAR(80) NULL,
    confidence_pct DECIMAL(8,4) NULL,
    risk_flag VARCHAR(120) NULL,
    priority_rank INT NULL,
    notes VARCHAR(1500) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NULL,
    PRIMARY KEY (run_id, scrip, assetclass),
    KEY idx_fusion_verdict_scrip (scrip),
    KEY idx_fusion_verdict_rank (run_id, priority_rank),
    KEY idx_fusion_verdict_final (fusion_verdict),
    CONSTRAINT fk_fusion_verdict_run
        FOREIGN KEY (run_id) REFERENCES jstockdata_fusion_run (run_id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS jstockdata_fusion_position_action (
    run_id BIGINT NOT NULL,
    broker VARCHAR(50) NOT NULL,
    account_name VARCHAR(120) NOT NULL,
    scrip VARCHAR(20) NOT NULL,
    assetclass VARCHAR(30) NOT NULL,
    segment VARCHAR(30) NULL,
    qty DECIMAL(18,6) NULL,
    avg_cost DECIMAL(18,4) NULL,
    position_value DECIMAL(18,4) NULL,
    current_price DECIMAL(18,4) NULL,
    unrealized_pl_pct DECIMAL(10,4) NULL,
    suggested_action VARCHAR(120) NULL,
    option_action VARCHAR(120) NULL,
    target_entry DECIMAL(18,4) NULL,
    target_exit DECIMAL(18,4) NULL,
    target_stop DECIMAL(18,4) NULL,
    confidence_pct DECIMAL(8,4) NULL,
    notes VARCHAR(1500) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (run_id, broker, account_name, scrip, assetclass),
    KEY idx_fusion_position_scrip (scrip),
    KEY idx_fusion_position_action (run_id, suggested_action),
    CONSTRAINT fk_fusion_position_run
        FOREIGN KEY (run_id) REFERENCES jstockdata_fusion_run (run_id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS jstockdata_fusion_history (
    history_id BIGINT NOT NULL AUTO_INCREMENT,
    run_id BIGINT NOT NULL,
    scrip VARCHAR(20) NOT NULL,
    assetclass VARCHAR(30) NOT NULL,
    analysis_date DATE NOT NULL,
    fusion_score DECIMAL(10,4) NULL,
    fusion_verdict VARCHAR(120) NULL,
    direction VARCHAR(80) NULL,
    confidence_pct DECIMAL(8,4) NULL,
    short_term_score DECIMAL(10,4) NULL,
    mid_term_score DECIMAL(10,4) NULL,
    long_term_score DECIMAL(10,4) NULL,
    sell_put_score DECIMAL(10,4) NULL,
    sell_call_score DECIMAL(10,4) NULL,
    investment_score DECIMAL(10,4) NULL,
    risk_score DECIMAL(10,4) NULL,
    realized_return_1w_pct DECIMAL(10,4) NULL,
    realized_return_1m_pct DECIMAL(10,4) NULL,
    realized_return_3m_pct DECIMAL(10,4) NULL,
    realized_return_6m_pct DECIMAL(10,4) NULL,
    realized_return_12m_pct DECIMAL(10,4) NULL,
    notes VARCHAR(1500) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (history_id),
    UNIQUE KEY uq_fusion_history_run_scrip (run_id, scrip, assetclass),
    KEY idx_fusion_history_scrip_date (scrip, analysis_date),
    KEY idx_fusion_history_analysis_date (analysis_date),
    CONSTRAINT fk_fusion_history_run
        FOREIGN KEY (run_id) REFERENCES jstockdata_fusion_run (run_id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

