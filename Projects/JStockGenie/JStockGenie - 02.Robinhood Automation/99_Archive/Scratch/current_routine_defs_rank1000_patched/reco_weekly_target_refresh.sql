CREATE DEFINER=`admin`@`%` PROCEDURE `reco_weekly_target_refresh`()
BEGIN
  DECLARE v_generated_at DATETIME DEFAULT NOW();

  CREATE TABLE IF NOT EXISTS `jstockdata_reco_weekly_target_recos` (
    `reco_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `generated_at` DATETIME NOT NULL,
    `reco_category` VARCHAR(20) NOT NULL,
    `account_scope` VARCHAR(40) NOT NULL,
    `target_rank` INT NOT NULL,
    `scrip` VARCHAR(20) NOT NULL,
    `assetclass` VARCHAR(30) NULL,
    `source_table` VARCHAR(64) NOT NULL,
    `frequency` VARCHAR(20) NULL,
    `trade_signal` VARCHAR(10) NULL,
    `direction` VARCHAR(10) NULL,
    `option_trade` VARCHAR(20) NULL,
    `option_type` VARCHAR(4) NULL,
    `option_side` VARCHAR(4) NULL,
    `strike_price` DECIMAL(12,2) NULL,
    `exp_date` CHAR(8) NULL,
    `dte` INT NULL,
    `premium` DECIMAL(12,4) NULL,
    `premium_roi_pct` DECIMAL(10,4) NULL,
    `current_price` DECIMAL(12,2) NULL,
    `target_profit_min_pct` DECIMAL(6,2) NOT NULL DEFAULT 1.00,
    `target_profit_max_pct` DECIMAL(6,2) NOT NULL DEFAULT 3.00,
    `target_profit_pct` DECIMAL(10,2) NULL,
    `weeklyized_target_profit_pct` DECIMAL(10,2) NULL,
    `stop_review_pct` DECIMAL(10,2) NULL,
    `expected_return_pct` DECIMAL(10,2) NULL,
    `upward_projection_pct` DECIMAL(10,2) NULL,
    `upward_probability_pct` DECIMAL(6,2) NULL,
    `downward_projection_pct` DECIMAL(10,2) NULL,
    `downward_probability_pct` DECIMAL(6,2) NULL,
    `risk_reward_ratio` DECIMAL(10,2) NULL,
    `projection_sample_size` INT NULL,
    `projection_confidence_score` DECIMAL(6,2) NULL,
    `recommendation_score` DECIMAL(10,2) NULL,
    `news_swing_signal` VARCHAR(20) NULL,
    `news_options_signal` VARCHAR(30) NULL,
    `news_sentiment_score` DECIMAL(10,2) NULL,
    `news_catalyst_score` DECIMAL(10,2) NULL,
    `news_risk_score` DECIMAL(10,2) NULL,
    `news_top_headline` VARCHAR(500) NULL,
    `news_top_url` VARCHAR(1000) NULL,
    `target_band_status` VARCHAR(20) NOT NULL,
    `notes` VARCHAR(500) NULL,
    PRIMARY KEY (`reco_id`),
    KEY `ix_weekly_target_category_rank` (`reco_category`, `target_rank`),
    KEY `ix_weekly_target_scrip` (`scrip`),
    KEY `ix_weekly_target_generated` (`generated_at`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

  TRUNCATE TABLE `jstockdata_reco_weekly_target_recos`;

  INSERT INTO `jstockdata_reco_weekly_target_recos` (
    generated_at, reco_category, account_scope, target_rank, scrip, assetclass,
    source_table, frequency, trade_signal, direction, current_price,
    target_profit_pct, weeklyized_target_profit_pct, stop_review_pct, expected_return_pct, upward_projection_pct,
    upward_probability_pct, downward_projection_pct, downward_probability_pct,
    risk_reward_ratio, projection_sample_size, projection_confidence_score,
    recommendation_score, news_swing_signal, news_options_signal,
    news_sentiment_score, news_catalyst_score, news_risk_score,
    news_top_headline, news_top_url, target_band_status, notes
  )
  SELECT
    v_generated_at, 'EQT', 'Agentic Account', @eqt_rank := @eqt_rank + 1,
    ranked.scrip, ranked.assetclass, 'jstockdata_reco_trade', ranked.frequency,
    ranked.trade_signal, ranked.trade_signal, ranked.close,
    ranked.target_profit_pct, ranked.target_profit_pct, -2.50, ranked.expected_return_pct,
    ranked.upward_projection_pct, ranked.upward_probability_pct,
    ranked.downward_projection_pct, ranked.downward_probability_pct,
    ranked.risk_reward_ratio, ranked.projection_sample_size,
    ranked.projection_confidence_score, ranked.target_score,
    ranked.swing_news_signal, ranked.options_news_signal,
    ranked.news_sentiment_score, ranked.catalyst_score, ranked.news_risk_score,
    ranked.top_headline, ranked.top_url, ranked.target_band_status,
    CONCAT('Weekly 1%-3% target screen. ', ranked.target_band_status,
           '; news=', ranked.swing_news_signal,
           '; preserve 25% cash buffer and review live quote before order.')
  FROM (
    SELECT
      t.*,
      COALESCE(n.swing_news_signal, 'NO_RECENT_NEWS') AS swing_news_signal,
      COALESCE(n.options_news_signal, 'NO_RECENT_NEWS') AS options_news_signal,
      COALESCE(n.news_sentiment_score, 0) AS news_sentiment_score,
      COALESCE(n.catalyst_score, 0) AS catalyst_score,
      COALESCE(n.news_risk_score, 0) AS news_risk_score,
      n.top_headline,
      n.top_url,
      LEAST(3.00, GREATEST(1.00, COALESCE(t.expected_return_pct, t.upward_projection_pct, t.backtest_avg_trade_return_pct, 1.00))) AS target_profit_pct,
      CASE
        WHEN COALESCE(t.expected_return_pct, t.upward_projection_pct, 0) BETWEEN 1.00 AND 3.00 THEN 'IN_BAND'
        WHEN COALESCE(t.expected_return_pct, t.upward_projection_pct, 0) > 3.00 THEN 'ABOVE_BAND'
        ELSE 'NEAR_BAND'
      END AS target_band_status,
      (
        100
        - ABS(LEAST(3.00, GREATEST(1.00, COALESCE(t.expected_return_pct, t.upward_projection_pct, 1.00))) - 2.00) * 12
        + COALESCE(t.upward_probability_pct, 0) * 0.25
        - COALESCE(t.downward_probability_pct, 50) * 0.25
        + LEAST(COALESCE(t.risk_reward_ratio, 0), 8) * 3
        + COALESCE(t.projection_confidence_score, 0) * 0.30
        - GREATEST(COALESCE(t.expected_return_pct, 0) - 3.00, 0) * 4
        + CASE COALESCE(n.swing_news_signal, 'NO_RECENT_NEWS')
            WHEN 'BULLISH_CATALYST' THEN 8
            WHEN 'BEARISH_CATALYST' THEN -10
            WHEN 'NEWS_RISK_AVOID' THEN -25
            ELSE 0
          END
        + LEAST(8, GREATEST(-8, COALESCE(n.news_sentiment_score, 0) * 0.10))
        - LEAST(20, COALESCE(n.news_risk_score, 0) * 0.25)
      ) AS target_score
    FROM `jstockdata_reco_trade` t
    JOIN `jstockdata_scrips` s
      ON s.`Scrip` = t.scrip
     AND UPPER(TRIM(COALESCE(s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(s.`RecoUniverseRank`, 999999) <= 1000
    LEFT JOIN `jstockdata_reco_news_signal` n ON n.scrip = t.scrip
    WHERE t.assetclass = 'EQ'
      AND t.trade_signal = 'BUY'
      AND COALESCE(t.expected_return_pct, t.upward_projection_pct, t.backtest_avg_trade_return_pct, 0) >= 0.75
      AND COALESCE(t.upward_probability_pct, 0) >= 60
      AND COALESCE(t.downward_probability_pct, 100) <= 35
      AND COALESCE(t.risk_reward_ratio, 0) >= 1.20
      AND COALESCE(t.projection_confidence_score, 0) >= 45
      AND COALESCE(t.backtest_worst_trade_pct, -99) >= -12
    ORDER BY target_score DESC, FIELD(t.frequency, 'DAILY', 'WEEKLY'), t.`rank`, t.scrip
    LIMIT 10
  ) ranked
  CROSS JOIN (SELECT @eqt_rank := 0) vars;

  INSERT INTO `jstockdata_reco_weekly_target_recos` (
    generated_at, reco_category, account_scope, target_rank, scrip, assetclass,
    source_table, frequency, trade_signal, direction, current_price,
    target_profit_pct, weeklyized_target_profit_pct, stop_review_pct, expected_return_pct, upward_projection_pct,
    upward_probability_pct, downward_projection_pct, downward_probability_pct,
    risk_reward_ratio, projection_sample_size, projection_confidence_score,
    recommendation_score, news_swing_signal, news_options_signal,
    news_sentiment_score, news_catalyst_score, news_risk_score,
    news_top_headline, news_top_url, target_band_status, notes
  )
  SELECT
    v_generated_at, 'ETF', 'ETF Basket Review', @etf_rank := @etf_rank + 1,
    ranked.scrip, ranked.assetclass, 'jstockdata_reco_trade', ranked.frequency,
    ranked.trade_signal, ranked.trade_signal, ranked.close,
    ranked.target_profit_pct, ranked.target_profit_pct, -2.00, ranked.expected_return_pct,
    ranked.upward_projection_pct, ranked.upward_probability_pct,
    ranked.downward_projection_pct, ranked.downward_probability_pct,
    ranked.risk_reward_ratio, ranked.projection_sample_size,
    ranked.projection_confidence_score, ranked.target_score,
    ranked.swing_news_signal, ranked.options_news_signal,
    ranked.news_sentiment_score, ranked.catalyst_score, ranked.news_risk_score,
    ranked.top_headline, ranked.top_url, ranked.target_band_status,
    CONCAT('Weekly ETF 1%-3% target screen. ', ranked.target_band_status,
           '; news=', ranked.swing_news_signal,
           '; use basket sizing and review live spread/liquidity.')
  FROM (
    SELECT
      t.*,
      COALESCE(n.swing_news_signal, 'NO_RECENT_NEWS') AS swing_news_signal,
      COALESCE(n.options_news_signal, 'NO_RECENT_NEWS') AS options_news_signal,
      COALESCE(n.news_sentiment_score, 0) AS news_sentiment_score,
      COALESCE(n.catalyst_score, 0) AS catalyst_score,
      COALESCE(n.news_risk_score, 0) AS news_risk_score,
      n.top_headline,
      n.top_url,
      LEAST(3.00, GREATEST(1.00, COALESCE(t.expected_return_pct, t.upward_projection_pct, t.backtest_avg_trade_return_pct, 1.00))) AS target_profit_pct,
      CASE
        WHEN COALESCE(t.expected_return_pct, t.upward_projection_pct, 0) BETWEEN 1.00 AND 3.00 THEN 'IN_BAND'
        WHEN COALESCE(t.expected_return_pct, t.upward_projection_pct, 0) > 3.00 THEN 'ABOVE_BAND'
        ELSE 'NEAR_BAND'
      END AS target_band_status,
      (
        100
        - ABS(LEAST(3.00, GREATEST(1.00, COALESCE(t.expected_return_pct, t.upward_projection_pct, 1.00))) - 2.00) * 14
        + COALESCE(t.upward_probability_pct, 0) * 0.28
        - COALESCE(t.downward_probability_pct, 50) * 0.30
        + LEAST(COALESCE(t.risk_reward_ratio, 0), 8) * 3
        + COALESCE(t.projection_confidence_score, 0) * 0.35
        - GREATEST(COALESCE(t.expected_return_pct, 0) - 3.00, 0) * 6
        + CASE COALESCE(n.swing_news_signal, 'NO_RECENT_NEWS')
            WHEN 'BULLISH_CATALYST' THEN 6
            WHEN 'BEARISH_CATALYST' THEN -8
            WHEN 'NEWS_RISK_AVOID' THEN -20
            ELSE 0
          END
        + LEAST(6, GREATEST(-6, COALESCE(n.news_sentiment_score, 0) * 0.08))
        - LEAST(18, COALESCE(n.news_risk_score, 0) * 0.20)
      ) AS target_score
    FROM `jstockdata_reco_trade` t
    JOIN `jstockdata_scrips` s
      ON s.`Scrip` = t.scrip
     AND UPPER(TRIM(COALESCE(s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(s.`RecoUniverseRank`, 999999) <= 1000
    LEFT JOIN `jstockdata_reco_news_signal` n ON n.scrip = t.scrip
    WHERE t.assetclass = 'ETF'
      AND t.trade_signal = 'BUY'
      AND COALESCE(t.expected_return_pct, t.upward_projection_pct, t.backtest_avg_trade_return_pct, 0) >= 0.75
      AND COALESCE(t.upward_probability_pct, 0) >= 65
      AND COALESCE(t.downward_probability_pct, 100) <= 35
      AND COALESCE(t.risk_reward_ratio, 0) >= 1.20
      AND COALESCE(t.projection_confidence_score, 0) >= 40
      AND COALESCE(t.backtest_worst_trade_pct, -99) >= -8
    ORDER BY target_score DESC, FIELD(t.frequency, 'DAILY', 'WEEKLY'), t.`rank`, t.scrip
    LIMIT 10
  ) ranked
  CROSS JOIN (SELECT @etf_rank := 0) vars;

  INSERT INTO `jstockdata_reco_weekly_target_recos` (
    generated_at, reco_category, account_scope, target_rank, scrip, assetclass,
    source_table, direction, option_trade, option_type, option_side, strike_price,
    exp_date, dte, premium, premium_roi_pct, current_price, target_profit_pct,
    weeklyized_target_profit_pct,
    stop_review_pct, expected_return_pct, upward_projection_pct, upward_probability_pct,
    downward_projection_pct, downward_probability_pct, projection_confidence_score,
    recommendation_score, news_swing_signal, news_options_signal,
    news_sentiment_score, news_catalyst_score, news_risk_score,
    news_top_headline, news_top_url, target_band_status, notes
  )
  SELECT
    v_generated_at, 'OPTIONS', 'Non-Agentic Manual Only', @opt_rank := @opt_rank + 1,
    ranked.scrip, ranked.assetclass, 'jstockdata_reco_options', ranked.direction,
    ranked.option_trade, ranked.option_type, ranked.option_side, ranked.strike_price,
    ranked.exp_date, ranked.dte, ranked.premium, ranked.premium_roi_pct,
    ranked.close_price, ranked.premium_roi_pct, ranked.weeklyized_premium_roi_pct, -2.00,
    ranked.expected_underlying_move_pct, ranked.underlying_upward_projection_pct,
    ranked.underlying_upward_probability_pct, ranked.underlying_downward_projection_pct,
    ranked.underlying_downward_probability_pct, ranked.underlying_projection_confidence_score,
    ranked.target_score, ranked.swing_news_signal, ranked.options_news_signal,
    ranked.news_sentiment_score, ranked.catalyst_score, ranked.news_risk_score,
    ranked.top_headline, ranked.top_url, ranked.target_band_status,
    CONCAT('Manual non-Agentic options screen for 1%-3% weeklyized premium ROI. ',
           ranked.target_band_status,
           '; news=', ranked.options_news_signal,
           '; use covered calls or cash-secured puts only; verify option chain liquidity before order.')
  FROM (
    SELECT
      o.*,
      COALESCE(n.swing_news_signal, 'NO_RECENT_NEWS') AS swing_news_signal,
      COALESCE(n.options_news_signal, 'NO_RECENT_NEWS') AS options_news_signal,
      COALESCE(n.news_sentiment_score, 0) AS news_sentiment_score,
      COALESCE(n.catalyst_score, 0) AS catalyst_score,
      COALESCE(n.news_risk_score, 0) AS news_risk_score,
      n.top_headline,
      n.top_url,
      ROUND(o.premium_roi_pct * 7 / NULLIF(o.dte, 0), 2) AS weeklyized_premium_roi_pct,
      CASE
        WHEN ROUND(o.premium_roi_pct * 7 / NULLIF(o.dte, 0), 2) BETWEEN 1.00 AND 3.00 THEN 'IN_BAND'
        WHEN ROUND(o.premium_roi_pct * 7 / NULLIF(o.dte, 0), 2) BETWEEN 0.50 AND 0.99 THEN 'NEAR_BAND'
        ELSE 'BELOW_BAND'
      END AS target_band_status,
      (
        100
        - ABS(ROUND(o.premium_roi_pct * 7 / NULLIF(o.dte, 0), 2) - 2.00) * 15
        + COALESCE(o.probability_pct, 0) * 0.35
        + COALESCE(o.recommendation_score, 0) * 0.25
        + COALESCE(o.underlying_projection_confidence_score, 30) * 0.10
        + CASE
            WHEN o.option_trade = 'SELL PUT' AND COALESCE(n.options_news_signal, 'NO_RECENT_NEWS') = 'SUPPORTS_SELL_PUT' THEN 8
            WHEN o.option_trade = 'SELL CALL' AND COALESCE(n.options_news_signal, 'NO_RECENT_NEWS') = 'SUPPORTS_SELL_CALL' THEN 8
            WHEN COALESCE(n.options_news_signal, 'NO_RECENT_NEWS') IN ('AVOID_SHORT_PREMIUM_EVENT', 'AVOID_OPTIONS_NEWS_RISK') THEN -30
            ELSE 0
          END
        - LEAST(20, COALESCE(n.news_risk_score, 0) * 0.25)
      ) AS target_score
    FROM `jstockdata_reco_options` o
    JOIN `jstockdata_scrips` s
      ON s.`Scrip` = o.scrip
     AND UPPER(TRIM(COALESCE(s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'
     AND COALESCE(s.`RecoUniverseRank`, 999999) <= 1000
    LEFT JOIN `jstockdata_reco_news_signal` n ON n.scrip = o.scrip
    WHERE o.option_side = 'SELL'
      AND o.option_trade IN ('SELL PUT', 'SELL CALL')
      AND o.premium_roi_pct > 0
      AND ROUND(o.premium_roi_pct * 7 / NULLIF(o.dte, 0), 2) >= 0.50
      AND COALESCE(o.probability_pct, 0) >= 70
      AND COALESCE(o.recommendation_score, 0) >= 70
      AND COALESCE(o.dte, 999) BETWEEN 5 AND 60
      AND o.premium IS NOT NULL
      AND o.strike_price IS NOT NULL
      AND COALESCE(n.options_news_signal, 'NO_RECENT_NEWS') NOT IN ('AVOID_SHORT_PREMIUM_EVENT', 'AVOID_OPTIONS_NEWS_RISK')
    ORDER BY FIELD(target_band_status, 'IN_BAND', 'NEAR_BAND', 'BELOW_BAND'),
             target_score DESC, o.probability_pct DESC, o.premium_roi_pct DESC, o.scrip
    LIMIT 20
  ) ranked
  CROSS JOIN (SELECT @opt_rank := 0) vars;

  CALL reco_runlog_mark('reco_weekly_target_refresh', 'SUCCESS',
                        CONCAT('Generated weekly 1%-3% target rows at ', v_generated_at));
END