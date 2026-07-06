# Runbooks

Current operating documents for the Robinhood automation workflow.

## Primary Files

- `Weekly_Trading_Operations_Runbook.md` - start here for the weekly step-by-step process.
- `Reco_SQL_Refresh_Runbook.md` - SQL wrapper sequence, freshness rules, validation queries, projection, target-band, and momentum guidance.
- `Reco_Model_Projection_Momentum_Design.md` - design notes for the projection and momentum model layers.

## Weekly Rule Of Thumb

If the user says they completed EOD upload, Java Trend, and SQL routines, check `jstockdata_reco_routine_runlog` first. If the refresh is recent, do not rerun SQL; generate recommendations from current tables.
