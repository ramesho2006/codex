# Current Position Analysis Routine

Trigger phrase:

```text
Perform Current Position Analysis
```

## Source

Read:

```text
O:\DB001A-MYFILES\01.Personal\India Investments\My Investment Positions.csv
```

## Steps

1. Parse the combined positions CSV.
2. Split by `Segment` into stock and option positions.
3. Analyze:
   - Robinhood Options
   - Robinhood Stocks
   - Fidelity Stocks
4. Use current market/option data where available, with source CSV marks as fallback.
5. Produce a crisp output at this grain:
   - `Analysis Date`
   - `Broker`
   - `Segment`
   - `Scrip`
   - `Buy/Sell/Hold`
6. De-duplicate rows at `Broker + Segment + Scrip + Buy/Sell/Hold`.
7. Refresh MySQL table `jstockdata_current_positions`:
   - create the table if it does not exist
   - delete existing rows
   - insert the latest records from the source CSV
   - populate `analysis_date` and `reco_action` from the analysis CSV

## Output

Create:

```text
O:\DB001A-MYFILES\01.Personal\India Investments\My Investment Positions Analysis <YYYY_MM_DD>.csv
```

Example:

```text
O:\DB001A-MYFILES\01.Personal\India Investments\My Investment Positions Analysis 2026_07_19.csv
```

## Database Loader

Use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Codex\Projects\JStockGenie\JStockGenie - 04.Robinhood Analysis\load_current_positions_to_mysql.ps1"
```

The loader reads the source and analysis CSVs, then refreshes:

```text
jstockdata_current_positions
```
