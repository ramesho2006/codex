# JStockGenie - 01. ETL, Trend, Backtest, Recos

Date: 2026-06-20

This folder is the project checkpoint for the Codex work covering JStockGenie ETL, trend building, backtests, stock/ETF recommendations, and options recommendations.

## Project Scope

- Upload EOD stock data to MySQL from the Java program.
- Build stock trend model data from the Java program.
- Run weekly recommendations for stock/ETF trading.
- Run weekly options recommendations for calls and puts.
- Enrich options recommendations with Yahoo Finance option-chain data from Java.
- Keep the workflow as one Java-driven routine instead of adding Python as a runtime layer.

## Main Files

- Java source:
  `D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie\JStockGenie.java`

- Java launcher:
  `D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie\run-jstockgenie.bat`

- Runbook:
  `D:\CodexNew\JStockGenie\RUNBOOK.md`

- MySQL helper script:
  `D:\CodexNew\JStockGenie\inspect-mysql57-schema.ps1`

- SQL routines folder:
  `D:\DB011-JWORK\JProgramming\MySQL\07.Codex SQL Routines\JStockGenie_Reco_Routines`

## Java Changes Completed

- Added Java recommendation runner methods:
  - `JStockDataPrintResultSet`
  - `JStockDataRunStoredProcedure`
  - `JStockDataRunRecommendations`
  - `JStockDataRunOptionsRecommendations`

- Added command support:
  - `TREND`
  - `RECO`
  - `OPTIONS`
  - `ALL`
  - `SUMMARY`

- Updated `TREND` and `ALL` so recommendations run after trend data is built.

- Added Java-only Yahoo Finance enrichment for option premiums:
  - Fetches Yahoo option-chain data.
  - Updates `jstockdata_reco_options`.
  - Populates `premium`, `premium_score`, `premium_roi_pct`, `implied_volatility`, `premium_source`, `market_data_provider`, and `market_data_asof`.

- Added SSL fallback for Yahoo Finance because the local Java certificate store rejected Yahoo certificates.

- Added `run-jstockgenie.bat` so external jars are included correctly at runtime.

## Java Dependencies Added

Folder:
`D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie\lib`

Jars:

- `commons-io-2.16.1.jar`
- `commons-math3-3.6.1.jar`
- `javax.activation-1.2.0.jar`
- `javax.mail-1.6.2.jar`
- `json-20240303.jar`

Existing MySQL driver:
`D:\DB011-JWORK\MyJARs\mysql-connector.jar`

## Build And Run

Compile:

```bat
cd /d D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie
javac -cp "..;lib\*" JStockGenie.java
```

Run full trend plus recommendations:

```bat
cd /d D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie
run-jstockgenie.bat TREND
```

Run recommendations only:

```bat
run-jstockgenie.bat RECO
```

Run options recommendations and Yahoo enrichment only:

```bat
run-jstockgenie.bat OPTIONS
```

## Database Work Completed

- MySQL 5.7 cloud connection was verified.
- Database checked: `jstocksnp`.
- Recommendation stored routines inspected and connected to Java execution.
- `reco_backtest()` was patched and redeployed to normalize frequency values with carriage-return cleanup.
- `jstockdata_summary`.`AVG GAIN VOLUME` was altered from `INT UNSIGNED` to `BIGINT UNSIGNED` to fix quarterly import truncation.
- `jstockdata_reco_options` was altered to add `premium_score`.

## Validation Results

Java `RECO` completed successfully:

- backtest rows: 40
- trade recommendation rows: 22
- investment recommendation rows: 6
- basket current rows: 20
- options recommendation rows: 1230

Java `OPTIONS` completed Yahoo enrichment:

- Yahoo option rows enriched: 872
- Yahoo option rows skipped: 358
- premium populated: 872
- premium score populated: 872
- premium ROI populated: 872
- implied volatility populated: 872

Skipped option rows generally mean Yahoo did not have a matching option contract for that ticker, expiration, option type, or strike at the time of lookup.

## Backups

Java backups created:

- `D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie\JSTockGenie.java.backup_20260619_codex_reco`
- `D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie\JStockGenie.java.backup_20260620_yahoo_options`

## Robinhood Notes

- Robinhood access was checked.
- One agentic-enabled account was visible, nickname `My Agentic`, ending `2224`.
- Other accounts were readable but not agentic-enabled.
- Stock/ETF automation should use only an agentic-enabled account.
- Options should remain manual unless a separate approved workflow is created.

## Recommended Next Steps

1. Run `run-jstockgenie.bat TREND` for the normal weekly workflow.
2. Review `jstockdata_reco_trade`, `jstockdata_reco_invest`, and `jstockdata_reco_options`.
3. Investigate the 358 skipped Yahoo option rows only if those rows are important for trading decisions.
4. Add a trading approval gate before any Robinhood stock/ETF automation.
5. Keep options trading manual for now.

