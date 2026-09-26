# JStockGenie Java Process Flow

Source reviewed: `D:\DB011-JWORK\JProgramming\MyJava\workspace\JStockGenie\JStockGenie.java`

```mermaid
flowchart TD
    A["Start: java JStockGenie ConfigFile Option [/debug|/stats]"] --> B{"Valid command?"}
    B -- "No" --> B1["Print usage and exit"]
    B -- "Yes" --> C["Read config file<br/>JStockDataGlobalSettings"]
    C --> C1["Load DB, paths, stock list, dates, frequency settings"]
    C1 --> D["Connect to MySQL 8<br/>JStockDataDBConnect"]
    D --> E{"Command option"}

    E -- "CREATE or ALL" --> F["Check QuotesPath files"]
    F --> F1{"Files found?"}
    F1 -- "Yes" --> F2["Create CSV import files<br/>JStockDataCreator"]
    F1 -- "No" --> F3["Print no data files"]

    E -- "IMPORT or ALL" --> G["Check quote files"]
    G --> G1{"Files found?"}
    G1 -- "Yes" --> G2["Clean tables<br/>JStockDataCleanUp"]
    G2 --> G3["LOAD DATA LOCAL INFILE<br/>into jstockdata_curr and jstockdata_hist"]
    G1 -- "No" --> G4["Print no files to import"]

    E -- "EXPORT, TREND, SUMMARY, or ALL" --> H["Determine frequency loop<br/>DAILY/WEEKLY/MONTHLY/QUARTERLY or configured frequency"]
    H --> I["For each frequency"]
    I --> I1["Set global dates<br/>JStockDataGlobalDates"]
    I1 --> J{"Frequency command branch"}

    J -- "EXPORT or ALL" --> K["Export scrip-wise quotes<br/>JStockDataExporterByScrip"]
    K --> K1["Query jstockdata_curr"]
    K1 --> K2["Write CSVEXPORT files"]

    J -- "TREND or ALL" --> L["Build HA trend files<br/>JStockDataTrendBuilder"]
    L --> L1["Read exported quote CSV by scrip"]
    L1 --> L2["Compute HA, RSI, SMA delta, LO delta, Combined Signal"]
    L2 --> L3["Write CSVTREND files"]
    L3 --> L4["Import main trend<br/>JStockDataTrendImporter -> jstockdata_hatrend"]
    L4 --> L5["Import extended trend<br/>JStockDataTrendImporter -> jstockdata_hatrend_extend"]
    L5 --> L6["Import summary<br/>JStockDataSummaryImporter -> jstockdata_summary"]
    L6 --> L7["Run stats SQL files<br/>JStockIndexTrend, JStockScripStats, HARecent, ReturnStats"]

    J -- "SUMMARY only" --> M["Import summary only<br/>JStockDataSummaryImporter"]

    F2 --> N{"Post-command reco branch"}
    F3 --> N
    G3 --> N
    G4 --> N
    K2 --> N
    L7 --> N
    M --> N
    B1 --> Z["End"]

    E -- "RECO" --> N
    N{"Option is TREND, ALL, or RECO?"}
    N -- "Yes" --> O["Weekly Recommendation Refresh<br/>JStockDataRunRecommendations(true)"]
    O --> O1["CALL reco_weekly_master_refresh"]
    O1 --> O2["SQL routine chain:<br/>reco_backtest -> reco_trade -> reco_invest -> reco_options -> reco_projection_refresh -> reco_projection_enrich_outputs -> reco_momentum_refresh -> reco_weekly_target_refresh"]
    O2 --> O3["Yahoo option premium enrichment<br/>JStockDataEnrichOptionsFromYahoo"]
    O3 --> O4["CALL reco_screener_refresh"]
    N -- "No" --> P{"Option is OPTIONS?"}

    E -- "OPTIONS" --> P
    P -- "Yes" --> P1["Options-only recommendation<br/>JStockDataRunOptionsRecommendations"]
    P1 --> P2["CALL reco_options"]
    P2 --> P3["Yahoo option premium enrichment"]
    P3 --> P4["CALL reco_screener_refresh"]
    P -- "No" --> Q{"Option is SCREEN or ALL?"}

    E -- "SCREEN" --> Q
    O4 --> Q
    P4 --> Q
    Q -- "Yes" --> R["Run screener<br/>JStockDataScreener"]
    R --> R1["CALL reco_screener_refresh"]
    R1 --> R2["Run JStockScreener.sql"]
    R2 --> R3["Build 15-column screener output"]
    R3 --> R4["Write CSVREPORT screener file"]
    R4 --> R5["Print screener and email attachment<br/>warn if SMTP TLS blocked"]
    Q -- "No" --> S{"Stats requested or ALL?"}

    R5 --> S
    S -- "Yes" --> S1["Write and print performance report<br/>JStockDataPerfReporter"]
    S -- "No" --> Z
    S1 --> Z["End"]
```

## Main Command Meanings

| Command | Primary Java path | Main output |
|---|---|---|
| `CREATE` | `JStockDataCreator` | CSV import files from raw quotes |
| `IMPORT` | `JStockDataCleanUp` -> `LOAD DATA LOCAL INFILE` | `jstockdata_curr`, `jstockdata_hist` |
| `EXPORT` | `JStockDataExporterByScrip` | Scrip-wise quote CSV files |
| `TREND` | `JStockDataTrendBuilder` -> trend imports -> recommendations | Trend tables, reco tables, screener refresh |
| `SUMMARY` | `JStockDataSummaryImporter` | `jstockdata_summary` |
| `RECO` | `JStockDataRunRecommendations(true)` | Weekly reco, options, screener tables |
| `OPTIONS` | `JStockDataRunOptionsRecommendations` | Options reco and screener refresh |
| `SCREEN` | `JStockDataScreener` | Screener CSV/report/email |
| `ALL` | Most paths in sequence | Full pipeline |

