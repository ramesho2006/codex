CREATE DEFINER=`admin`@`%` PROCEDURE `reco_options`()
BEGIN

    DECLARE v_target_date DATE;

    DECLARE v_month_start DATE;

    DECLARE v_expiration_date DATE;



    SET v_target_date = DATE_ADD(CURDATE(), INTERVAL 35 DAY);

    SET v_month_start = DATE_ADD(LAST_DAY(DATE_SUB(v_target_date, INTERVAL 1 MONTH)), INTERVAL 1 DAY);

    SET v_expiration_date = DATE_ADD(

        v_month_start,

        INTERVAL (MOD(4 - WEEKDAY(v_month_start) + 7, 7) + 14) DAY

    );



    TRUNCATE TABLE `jstockdata_reco_options`;



    DROP TEMPORARY TABLE IF EXISTS `tmp_option_base`;

    CREATE TEMPORARY TABLE `tmp_option_base` AS

    SELECT

        w.`SCRIP` AS `scrip`,

        s.`Rank` AS `rank_value`,

        UPPER(TRIM(s.`AssetClass`)) AS `assetclass`,

        w.`Close` AS `close_price`,

        CASE

            WHEN w.`Combined_Signal_Ind` IN ('BUY', 'SELL')

                THEN CAST(w.`DATE` AS CHAR)

            WHEN d.`Combined_Signal_Ind` IN ('BUY', 'SELL')

                THEN CAST(d.`DATE` AS CHAR)

            ELSE CAST(w.`DATE` AS CHAR)

        END AS `signal_date`,

        CASE

            WHEN w.`Combined_Signal_Ind` IN ('BUY', 'SELL') THEN 'WEEKLY'

            WHEN d.`Combined_Signal_Ind` IN ('BUY', 'SELL') THEN 'DAILY'

            ELSE 'WEEKLY'

        END AS `signal_chart`,

        CASE

            WHEN w.`Combined_Signal_Ind` IN ('BUY', 'SELL') THEN 'FRESH'

            ELSE 'ACTIVE'

        END AS `signal_status`,

        w.`Combined_Signal` AS `direction`,

        w.`Combined_Signal` AS `weekly_combined_signal`,

        d.`Combined_Signal` AS `daily_combined_signal`,

        CASE

            WHEN w.`Close` < 25 THEN 0.50

            WHEN w.`Close` < 200 THEN 1.00

            WHEN w.`Close` < 500 THEN 5.00

            ELSE 10.00

        END AS `strike_increment`,

        LEAST(

            85,

            58

            + CASE WHEN w.`Combined_Signal_Ind` IN ('BUY', 'SELL') THEN 10 ELSE 0 END

            + CASE WHEN w.`LODeltaSignal` = d.`LODeltaSignal` THEN 6 ELSE 0 END

            + CASE

                WHEN w.`Combined_Signal` = 'BUY' AND d.`HARSIValue` BETWEEN 45 AND 70 THEN 5

                WHEN w.`Combined_Signal` = 'SELL' AND d.`HARSIValue` BETWEEN 30 AND 55 THEN 5

                ELSE 0

              END

            + CASE

                WHEN w.`Combined_Signal` = 'BUY' AND h.`HARallySlope` > 0 THEN 4

                WHEN w.`Combined_Signal` = 'SELL' AND h.`HARallySlope` < 0 THEN 4

                ELSE 0

              END

        ) AS `probability_pct`,

        LEAST(

            100,

            45

            + CASE WHEN w.`Combined_Signal_Ind` IN ('BUY', 'SELL') THEN 20 ELSE 0 END

            + CASE WHEN w.`LODeltaSignal` = d.`LODeltaSignal` THEN 10 ELSE 0 END

            + CASE WHEN h.`CLOSE` * h.`volume` >= 100000000 THEN 10 ELSE 0 END

            + CASE

                WHEN w.`Combined_Signal` = 'BUY' AND h.`HARallySlope` > 0 THEN 10

                WHEN w.`Combined_Signal` = 'SELL' AND h.`HARallySlope` < 0 THEN 10

                ELSE 0

              END

        ) AS `recommendation_score`

    FROM `jstockdata_harecent_extend` w

    JOIN `jstockdata_harecent_extend` d

      ON d.`SCRIP` = w.`SCRIP`

     AND d.`FREQUENCY` = 'DAILY'

    JOIN `jstockdata_harecent` h

      ON h.`SCRIP` = w.`SCRIP`

     AND TRIM(REPLACE(h.`Frequency`, '\r', '')) = 'WEEKLY'

    JOIN `jstockdata_scrips` s

      ON s.`Scrip` = w.`SCRIP`

    WHERE w.`FREQUENCY` = 'WEEKLY'

      AND UPPER(TRIM(s.`AssetClass`)) IN ('EQ', 'ETF')
      AND UPPER(TRIM(COALESCE(s.`RecoUniverseStatus`, 'OMIT'))) = 'KEEP'

      AND w.`Combined_Signal` IN ('BUY', 'SELL')

      AND d.`Combined_Signal` = w.`Combined_Signal`

      AND w.`Close` > 0;



    DROP TEMPORARY TABLE IF EXISTS `tmp_option_base_sell`;

    CREATE TEMPORARY TABLE `tmp_option_base_sell` AS

    SELECT * FROM `tmp_option_base`;



    INSERT INTO `jstockdata_reco_options` (

        `generated_at`,

        `scrip`,

        `rank`,

        `assetclass`,

        `close_price`,

        `signal_date`,

        `signal_chart`,

        `signal_status`,

        `direction`,

        `option_trade`,

        `option_type`,

        `option_side`,

        `moneyness_target`,

        `strike_price`,

        `exp_date`,

        `dte`,

        `premium`,

        `premium_source`,

        `premium_roi_pct`,

        `implied_volatility`,

        `probability_pct`,

        `probability_type`,

        `recommendation_score`,

        `weekly_combined_signal`,

        `daily_combined_signal`,

        `market_data_provider`,

        `market_data_asof`

    )

    SELECT

        DATE_FORMAT(CURDATE(), '%Y%m%d'),

        `scrip`,

        `rank_value`,

        `assetclass`,

        `close_price`,

        `signal_date`,

        `signal_chart`,

        `signal_status`,

        `direction`,

        CASE WHEN `direction` = 'BUY' THEN 'BUY CALL' ELSE 'BUY PUT' END,

        CASE WHEN `direction` = 'BUY' THEN 'CALL' ELSE 'PUT' END,

        'BUY',

        'ATM-ITM',

        CASE

            WHEN `direction` = 'BUY' THEN FLOOR(`close_price` / `strike_increment`) * `strike_increment`

            ELSE CEIL(`close_price` / `strike_increment`) * `strike_increment`

        END,

        DATE_FORMAT(v_expiration_date, '%Y%m%d'),

        DATEDIFF(v_expiration_date, CURDATE()),

        NULL,

        NULL,

        NULL,

        NULL,

        `probability_pct`,

        'DIRECTIONAL_HEURISTIC',

        `recommendation_score`,

        `weekly_combined_signal`,

        `daily_combined_signal`,

        NULL,

        NULL

    FROM `tmp_option_base`

    UNION ALL

    SELECT

        DATE_FORMAT(CURDATE(), '%Y%m%d'),

        `scrip`,

        `rank_value`,

        `assetclass`,

        `close_price`,

        `signal_date`,

        `signal_chart`,

        `signal_status`,

        `direction`,

        CASE WHEN `direction` = 'BUY' THEN 'SELL PUT' ELSE 'SELL CALL' END,

        CASE WHEN `direction` = 'BUY' THEN 'PUT' ELSE 'CALL' END,

        'SELL',

        'OTM',

        CASE

            WHEN `direction` = 'BUY' THEN FLOOR((`close_price` * 0.95) / `strike_increment`) * `strike_increment`

            ELSE CEIL((`close_price` * 1.05) / `strike_increment`) * `strike_increment`

        END,

        DATE_FORMAT(v_expiration_date, '%Y%m%d'),

        DATEDIFF(v_expiration_date, CURDATE()),

        NULL,

        NULL,

        NULL,

        NULL,

        LEAST(90, `probability_pct` + 5),

        'DIRECTIONAL_HEURISTIC',

        `recommendation_score`,

        `weekly_combined_signal`,

        `daily_combined_signal`,

        NULL,

        NULL

    FROM `tmp_option_base_sell`;



    DROP TEMPORARY TABLE IF EXISTS `tmp_option_base`;

    DROP TEMPORARY TABLE IF EXISTS `tmp_option_base_sell`;



    -- SELECT

        -- `opportunity_id`,

        -- `generated_at`,

        -- `scrip`,

        -- `rank`,

        -- `assetclass`,

        -- `close_price`,

        -- `signal_date`,

        -- `signal_chart`,

        -- `signal_status`,

        -- `direction`,

        -- `option_trade`,

        -- `option_type`,

        -- `option_side`,

        -- `moneyness_target`,

        -- `strike_price`,

        -- `exp_date`,

        -- `dte`,

        -- `premium`,

        -- `premium_source`,

        -- `premium_roi_pct`,

        -- `implied_volatility`,

        -- `probability_pct`,

        -- `probability_type`,

        -- `recommendation_score`,

        -- `weekly_combined_signal`,

        -- `daily_combined_signal`,

        -- `market_data_provider`,

        -- `market_data_asof`

    -- FROM `jstockdata_reco_options`

    -- ORDER BY

        -- FIELD(`signal_status`, 'FRESH', 'ACTIVE'),

        -- `recommendation_score` DESC,

        -- `probability_pct` DESC,

        -- `rank`,

        -- `scrip`,

        -- `option_trade`;

END