# Weekly Dry Run Summary - 20260704

Practice run only. No order reviews were created and no orders were placed, changed, or cancelled.

## SQL Freshness
- reco_basket_refresh: SUCCESS at 2026-07-04 01:23:29 - Completed by reco_weekly_projection_refresh
- reco_options: SUCCESS at 2026-07-04 01:21:49 - Completed by reco_weekly_projection_refresh
- reco_weekly_projection_refresh: SUCCESS at 2026-07-04 01:23:29 - Completed wrapper; started at 2026-07-04 01:20:27
- reco_weekly_target_refresh: SUCCESS at 2026-07-04 19:00:56 - Generated weekly 1%-3% target rows at 2026-07-04 19:00:56

## Agentic Account Context
- Account: My Agentic ending 1224
- Account value: 1208.01360868
- Cash: 807.31
- Buying power: 597.43
- 25% cash buffer target: 302.00
- Existing queued orders from prior approved run remain untouched: SELL SYF, SELL GEV, BUY HWM, BUY CASY.

## EQT Dry Run
- Rows: 6
- #1 CASY: ABOVE_BAND, target 3.00%, expected 3.65%, up prob 100.00%, down prob 0.00%
- #2 VLO: IN_BAND, target 2.09%, expected 2.09%, up prob 83.33%, down prob 16.67%
- #3 MAS: ABOVE_BAND, target 3.00%, expected 7.96%, up prob 100.00%, down prob 0.00%
- #4 ETR: ABOVE_BAND, target 3.00%, expected 4.38%, up prob 100.00%, down prob 0.00%
- #5 AEP: ABOVE_BAND, target 3.00%, expected 3.56%, up prob 83.33%, down prob 16.67%
- #6 HWM: ABOVE_BAND, target 3.00%, expected 14.12%, up prob 100.00%, down prob 0.00%

## ETF Dry Run
- Rows: 2
- #1 IWV: IN_BAND, target 2.04%, expected 2.04%, risk/reward 10.55
- #2 IYF: IN_BAND, target 2.87%, expected 2.87%, risk/reward 4.38

## Manual Options Dry Run
- Rows: 20
- These are non-Agentic/manual-only candidates. Verify live option chain, bid/ask spread, volume/open interest, buying-power/collateral, and assignment risk before any manual order.
- #1 IHF SELL PUT 53.00 exp 20260821 DTE 48: weeklyized target 2.06%, total premium ROI 14.1321%
- #2 WDC SELL PUT 510.00 exp 20260821 DTE 48: weeklyized target 1.94%, total premium ROI 13.2794%
- #3 TER SELL PUT 350.00 exp 20260821 DTE 48: weeklyized target 1.90%, total premium ROI 13.0143%
- #4 COHR SELL PUT 310.00 exp 20260821 DTE 48: weeklyized target 1.84%, total premium ROI 12.6290%
- #5 INTC SELL PUT 115.00 exp 20260821 DTE 48: weeklyized target 1.71%, total premium ROI 11.6957%
- #6 AMAT SELL PUT 570.00 exp 20260821 DTE 48: weeklyized target 1.57%, total premium ROI 10.7895%
- #7 TTD SELL CALL 20.00 exp 20260821 DTE 48: weeklyized target 1.39%, total premium ROI 9.5000%
- #8 AMD SELL PUT 490.00 exp 20260821 DTE 48: weeklyized target 1.33%, total premium ROI 9.1276%
- #9 CHTR SELL CALL 145.00 exp 20260821 DTE 48: weeklyized target 1.31%, total premium ROI 9.0000%
- #10 DELL SELL PUT 370.00 exp 20260821 DTE 48: weeklyized target 1.30%, total premium ROI 8.9459%

## Files
- Weekly_EQT_Target_Band_20260704_DRY_RUN.csv
- Weekly_ETF_Target_Band_20260704_DRY_RUN.csv
- Weekly_Options_Manual_Recos_20260704_DRY_RUN.csv
- SQL_Runlog_Context_20260704_DRY_RUN.csv
