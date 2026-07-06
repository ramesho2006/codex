# JStockGenie - Robinhood Automation

This folder is organized around the weekly JStockGenie Robinhood workflow.

## Start Here

- `00_Runbooks/Weekly_Trading_Operations_Runbook.md` - primary weekly operating runbook.
- `00_Runbooks/Reco_SQL_Refresh_Runbook.md` - SQL freshness, refresh sequence, and validation queries.
- `01_Routines/` - routine-specific instructions for EQT, ETF, and options recommendation runs.

## Folder Map

- `00_Runbooks/` - current operating runbooks and model design notes.
- `01_Routines/` - stable routine definitions used when the user asks to run weekly routines.
- `02_SQL/` - SQL migrations and reusable review queries.
- `03_Reports/` - dated weekly outputs and dry-run reports.
- `04_Journal/` - Agentic trading journal workbook and previews.
- `05_Tools/` - local helper/build scripts.
- `99_Archive/` - old duplicate folders, scratch extracts, and historical artifacts kept for reference.

## Weekly Output Locations

- EQT Agentic reports: `03_Reports/EQT/YYYYMMDD`
- ETF basket reports: `03_Reports/ETF/YYYYMMDD`
- Dry runs: `03_Reports/DryRuns/YYYYMMDD`
- Agentic journal: `04_Journal/Agentic Trading Journal/Robinhood_MyAgentic_Trading_Journal.xlsx`

## Weekly Routine Summary

1. Upload EOD data.
2. Run Java Trend model.
3. Confirm SQL freshness or run `CALL reco_weekly_projection_refresh();` when approved.
4. Validate projections, momentum, baskets, and target-band tables.
5. Generate ETF, EQT, and manual options recommendations.
6. For Agentic account, prepare orders as review-only and place only after explicit confirmation.
7. For non-Agentic accounts, user manually reviews and places ETF/options trades.
8. Update the trading journal after fills, funds, or position changes.
