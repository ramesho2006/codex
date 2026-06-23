# JStockGenie Runbook

## Purpose

JStockGenie is the operating workflow for:

- Uploading EOD stock data into MySQL.
- Building the Heiken Ashi, SMA, RSI, large-order proxy, and combined-signal trend model.
- Refreshing weekly stock/ETF, basket, backtest, and options recommendations.
- Preparing approved stock/ETF basket actions for Robinhood Agentic trading.
- Keeping options recommendations manual until option-chain premiums and IV are enriched.

## Key Paths

Java source:

```text
D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie\JSTockGenie.java
```

Java source backup created before recommendation automation edits:

```text
D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie\JSTockGenie.java.backup_20260619_codex_reco
```

Codex project workspace:

```text
D:\CodexNew\JStockGenie
```

Recommendation SQL routine source:

```text
D:\DB011-JWORK\JProgramming\MySQL\07.Codex SQL Routines\JStockGenie_Reco_Routines
```

Main data root:

```text
D:\DB011-JWORK\JStockData
```

Trend work root:

```text
D:\DB011-JWORK\JStockTrend
```

## Database

Target database:

```text
jstocksnp
```

Core input tables produced by the Java EOD/trend pipeline:

```text
jstockdata_curr
jstockdata_hist
jstockdata_hatrend
jstockdata_hatrend_extend
jstockdata_summary
jstockdata_harecent
jstockdata_harecent_extend
jstockdata_scrips
```

Recommendation output tables:

```text
jstockdata_backtest_summary
jstockdata_reco_backtest
jstockdata_reco_trade
jstockdata_reco_invest
jstockdata_reco_basket_current
jstockdata_reco_basket_actions
jstockdata_reco_basket_history
jstockdata_reco_options
```

## Weekly Operating Sequence

1. Load or refresh EOD source files under the configured quotes folder.
2. Run Java import to upload EOD data into MySQL.
3. Run Java export and trend build.
4. Import trend output CSVs into `jstockdata_hatrend` and `jstockdata_hatrend_extend`.
5. Import summary output into `jstockdata_summary`.
6. Refresh derived recent tables:
   - `jstockdata_harecent`
   - `jstockdata_harecent_extend`
   - `jstockdata_returnstats`
7. Refresh recommendations.
8. Review basket actions before any Robinhood order placement.
9. Review options recommendations manually.

## Current Recommendation Automation Design

Recommended design:

- Keep recommendation logic as MySQL stored procedures.
- Let Java call those procedures automatically after trend refresh.
- Keep SQL routines as the canonical business logic because the recommendations are set-based calculations over large MySQL tables.

This avoids manual SQL execution without copying thousands of lines of SQL into Java strings.

Java commands added/planned:

```text
RECO    Runs stock/ETF recommendation routines.
OPTIONS Runs options recommendation routine.
TREND   Builds trends, imports summaries, then refreshes recommendations.
ALL     Runs full pipeline and refreshes recommendations.
```

Recommendation stored procedure order:

```sql
CALL reco_backtest();
CALL reco_trade();
CALL reco_invest();
CALL reco_basket_refresh();
CALL reco_options();
```

`run_recommendations()` currently calls:

```sql
CALL reco_backtest();
CALL reco_trade();
CALL reco_invest();
CALL reco_basket_refresh();
```

`reco_options()` is separate because options trades are manual-review only.

## Alternative: Java-Native Recommendation Functions

A full Java-native rewrite is possible, but it is not the preferred next step.

Reasons:

- The current logic uses large set operations, temporary tables, joins, ranking, grouping, and truncation/insert refreshes.
- MySQL is more efficient for this workload than row-by-row Java loops.
- Embedding large SQL blocks into Java makes maintenance harder.
- The existing SQL routines are already deployed and aligned with the live schema.

If stored procedures are not desired later, use this middle path instead:

- Keep SQL in external `.sql` files.
- Convert each procedure body into a plain executable SQL script.
- Add Java methods such as `JStockDataRecoBacktest()`, `JStockDataRecoTrade()`, `JStockDataRecoInvest()`, `JStockDataRecoBasketRefresh()`, and `JStockDataRecoOptions()`.
- Each Java method executes one SQL script statement-by-statement in a single JDBC session.

That gives Java function-level orchestration without burying the recommendation logic inside Java source code.

## Robinhood Safety Gate

Robinhood account access confirmed:

- One Agentic-enabled individual account is available for automated stock/ETF trading.
- Other accounts are readable but not Agentic-enabled for automated order placement.

Automation should use `jstockdata_reco_basket_actions` as the approval queue.

Rules:

- Never place an order from `PENDING_APPROVAL`.
- Require explicit approval before changing an action to approved/executable.
- Options remain manual-only.
- Use stock/ETF basket actions only for the Agentic-enabled account.

Suggested approval statuses:

```text
PENDING_APPROVAL
APPROVED
REJECTED
ORDER_REVIEWED
ORDER_PLACED
ORDER_FAILED
```

## Validation Checklist

After Java trend refresh:

```sql
SELECT COUNT(*) FROM jstockdata_hatrend;
SELECT COUNT(*) FROM jstockdata_hatrend_extend;
SELECT COUNT(*) FROM jstockdata_harecent;
SELECT COUNT(*) FROM jstockdata_harecent_extend;
```

After recommendations:

```sql
SELECT COUNT(*) FROM jstockdata_reco_backtest;
SELECT COUNT(*) FROM jstockdata_reco_trade;
SELECT COUNT(*) FROM jstockdata_reco_invest;
SELECT COUNT(*) FROM jstockdata_reco_basket_current;
SELECT COUNT(*) FROM jstockdata_reco_basket_actions;
SELECT COUNT(*) FROM jstockdata_reco_options;
```

Review latest basket batch:

```sql
SELECT *
FROM jstockdata_reco_basket_actions
WHERE batch_id = (
    SELECT batch_id
    FROM jstockdata_reco_basket_actions
    ORDER BY action_id DESC
    LIMIT 1
)
ORDER BY FIELD(action, 'SELL', 'TAPER', 'BUY', 'HOLD'), assetclass, symbol;
```

## Rollback

To restore the Java source to the pre-recommendation-automation state, use the backup:

```text
D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie\JSTockGenie.java.backup_20260619_codex_reco
```

Before rollback, save a copy of the current Java file if any new work should be preserved.

## Known Notes

- Java compile succeeds when run with the local `lib` jars and sibling `JCollection` classes on the classpath.
- The options recommendation routine currently leaves premium, IV, provider, and market data timestamp fields as `NULL`; add option-chain enrichment before relying on those fields for trade selection.
- Rename `reco_basktest.sql` to `reco_backtest.sql` when convenient so the filename matches the procedure name.
- `reco_basktest.sql` source was patched to normalize `Frequency` consistently with `TRIM(REPLACE(..., '\r', ''))`. The live MySQL `reco_backtest()` procedure was redeployed from this source on 2026-06-20.

## Stored Routine Review Notes

Accuracy:

- `reco_backtest()` should derive historical events from `Combined_Signal` changes. That is appropriate for backtesting completed BUY-to-SELL legs.
- `reco_trade()` and `reco_invest()` use fresh `Combined_Signal_Ind` events and current `jstockdata_harecent*` state. That is appropriate for current recommendations.
- `reco_basket_refresh()` should remain the bridge to automation because it creates explicit `BUY`, `SELL`, `TAPER`, and `HOLD` actions with `PENDING_APPROVAL`.
- `reco_options()` is directional only until premiums, IV, and chain data are populated.

Performance:

- The routines use temporary tables and add indexes before the larger joins. That is good for MySQL 5.7.
- The biggest base-table pressure points are `jstockdata_hatrend`, `jstockdata_hatrend_extend`, `jstockdata_harecent`, and `jstockdata_harecent_extend`.
- Recommended persistent indexes, if not already present:

```sql
CREATE INDEX ix_hatrend_symbol_freq_date
ON jstockdata_hatrend (SCRIP, Frequency, DATE);

CREATE INDEX ix_hatrend_extend_symbol_freq_date
ON jstockdata_hatrend_extend (SCRIP, FREQUENCY, DATE);

CREATE INDEX ix_harecent_symbol_freq_date
ON jstockdata_harecent (SCRIP, Frequency, DATE);

CREATE INDEX ix_harecent_extend_symbol_freq_date
ON jstockdata_harecent_extend (SCRIP, FREQUENCY, DATE);

CREATE INDEX ix_scrips_scrip_assetclass
ON jstockdata_scrips (Scrip, AssetClass);
```

Java integration:

- `TREND` and `ALL` call `JStockDataRunRecommendations(true)` after trend building/import/summary completes.
- `RECO` can refresh recommendations independently.
- `OPTIONS` can refresh only the options recommendation table.

## Java Build And Run

Local dependency jars:

```text
D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie\lib\commons-io-2.16.1.jar
D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie\lib\commons-math3-3.6.1.jar
D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie\lib\javax.activation-1.2.0.jar
D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie\lib\javax.mail-1.6.2.jar
D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie\lib\json-20240303.jar
```

Existing MySQL JDBC jar:

```text
D:\DB011-JWORK\MyJARs\mysql-connector.jar
```

Compile:

```bat
cd /d D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie
javac -cp "..;lib\*" JStockGenie.java
```

Refresh recommendations only:

```bat
cd /d D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie
java -cp ".;..;lib\*;D:\DB011-JWORK\MyJARs\mysql-connector.jar" JStockGenie "D:\DB011-JWORK\JStockTrend\config\JStockSNPConfig.ini" RECO
```

Refresh options only:

```bat
cd /d D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie
java -cp ".;..;lib\*;D:\DB011-JWORK\MyJARs\mysql-connector.jar" JStockGenie "D:\DB011-JWORK\JStockTrend\config\JStockSNPConfig.ini" OPTIONS
```

Recommended launcher:

```bat
cd /d D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie
run-jstockgenie.bat TREND
run-jstockgenie.bat RECO
run-jstockgenie.bat OPTIONS
```

The launcher includes `lib\*`, which is required for Yahoo option JSON parsing.

Latest Java `RECO` validation:

```text
jstockdata_reco_backtest: 40
jstockdata_reco_trade: 22
jstockdata_reco_invest: 6
jstockdata_reco_basket_current: 20
jstockdata_reco_options: 1230
latest basket action summary: HOLD = 20
```

## Yahoo Options Enrichment

`OPTIONS`, `RECO`, `TREND`, and `ALL` now use Java to enrich `jstockdata_reco_options` after `reco_options()` runs.

Updated fields:

```text
premium
premium_source
premium_roi_pct
premium_score
implied_volatility
market_data_provider
market_data_asof
```

Source:

```text
Yahoo Finance option chain
```

Implementation notes:

- `reco_options()` still creates the candidate rows.
- Java method `JStockDataEnrichOptionsFromYahoo()` fetches Yahoo option chains and updates the candidate rows.
- If Yahoo does not have a usable bid/ask or last price for a contract, that row is skipped and remains partially null.
- Latest test enriched 872 of 1230 option candidates.
