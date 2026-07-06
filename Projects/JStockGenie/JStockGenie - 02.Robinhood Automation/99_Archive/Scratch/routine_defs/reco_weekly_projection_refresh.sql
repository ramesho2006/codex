CREATE DEFINER=`admin`@`%` PROCEDURE `reco_weekly_projection_refresh`()
BEGIN
              DECLARE v_started_at datetime DEFAULT NOW();
              DECLARE v_current_step varchar(128) DEFAULT 'reco_weekly_projection_refresh';

              DECLARE EXIT HANDLER FOR SQLEXCEPTION
              BEGIN
                CALL reco_runlog_mark(v_current_step, 'FAILED', 'Failed during reco_weekly_projection_refresh');
                CALL reco_runlog_mark('reco_weekly_projection_refresh', 'FAILED', CONCAT('Failed wrapper; started at ', v_started_at));
                RESIGNAL;
              END;

              SET v_current_step = 'reco_backtest';
              CALL reco_backtest();
              CALL reco_runlog_mark('reco_backtest', 'SUCCESS', 'Completed by reco_weekly_projection_refresh');

              SET v_current_step = 'reco_trade';
              CALL reco_trade();
              CALL reco_runlog_mark('reco_trade', 'SUCCESS', 'Completed by reco_weekly_projection_refresh');

              SET v_current_step = 'reco_invest';
              CALL reco_invest();
              CALL reco_runlog_mark('reco_invest', 'SUCCESS', 'Completed by reco_weekly_projection_refresh');

              SET v_current_step = 'reco_options';
              CALL reco_options();
              CALL reco_runlog_mark('reco_options', 'SUCCESS', 'Completed by reco_weekly_projection_refresh');

              SET v_current_step = 'reco_projection_refresh';
              CALL reco_projection_refresh();
              CALL reco_runlog_mark('reco_projection_refresh', 'SUCCESS', 'Completed by reco_weekly_projection_refresh');

              SET v_current_step = 'reco_projection_enrich_outputs';
              CALL reco_projection_enrich_outputs();
              CALL reco_runlog_mark('reco_projection_enrich_outputs', 'SUCCESS', 'Completed by reco_weekly_projection_refresh');

              SET v_current_step = 'reco_basket_refresh';
              CALL reco_basket_refresh();
              CALL reco_runlog_mark('reco_basket_refresh', 'SUCCESS', 'Completed by reco_weekly_projection_refresh');

              CALL reco_runlog_mark('reco_weekly_projection_refresh', 'SUCCESS', CONCAT('Completed wrapper; started at ', v_started_at));
            END