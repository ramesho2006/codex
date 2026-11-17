# Weekly options recommendation archive — concise schema

Table: `jstocksnp.jstockdata_reco_weekly_optionstrat`. The corrected user column list is implemented exactly: 25 columns. Six October 31, 2026 recommendations were preserved with original IDs. `roi_pct`, `pop_pct` and `breakeven` retain midpoint estimates. `remark` retains the former recommendation status; detailed risk notes remain in `qualifications`.

The full original schema and data are retained in MySQL table `jstockdata_option_recommendations_backup_20261031_122639` and the local `schema-backup-20261031_122639` folder. Historical source reports and rich JSON snapshots remain available locally. Removed metadata and pricing columns are not recreated in the active table.

## Weekly imports

Use `analysis/optionstrat-20261031/recommendations_concise.json` as the field-layout example, replacing values with freshly verified review data. New rows omit `reco_id`; MySQL assigns it. An existing example ID is ignored by the importer. Dates must be ISO YYYY-MM-DD.

`collateral` is now a stored numeric input, not a generated column. Compute gross USD collateral before premium: CSP = short strike × quantity × leg multiplier; spreads = absolute strike width × quantity × leg multiplier. Keep the multiplier in each leg of `legs_json`; do not silently assume 100 for adjusted contracts. The importer validates collateral, leg details, delta bounds, DTE, midpoint breakeven and ROI.

Run validation first, then apply:

```powershell
python 'D:/Codex/Projects/JStockGenie/analysis/weekly-trend-options-review/import_recommendations.py' '<new-concise-snapshot.json>'
python 'D:/Codex/Projects/JStockGenie/analysis/weekly-trend-options-review/import_recommendations.py' '<new-concise-snapshot.json>' --apply
```

Uses `MYSQL80_URL` with PyMySQL. Exact retries compare retained fields and skip identical rows. The importer serializes its own runs with a MySQL advisory lock; it detects conflicts by review date, symbol, strategy, expiry, strikes and quantity, including NULL long strikes. Changed content under the same identity is rejected rather than overwritten. Direct SQL writers do not receive this importer-level duplicate protection. There is no hidden review key or hash column. Never invent a new review date solely to bypass a conflict; resolve a genuine same-day correction explicitly.

The prior one-time migration scripts `migrate_concise_schema.py` and `add_collateral.sql` are historical migration artifacts, not weekly commands. Do not rerun them against the concise schema.

## Query

```sql
SELECT reco_id, review_date, scrip, strategy, expiry_date, dte,
       short_strike, long_strike, delta_short_leg, delta_long_leg,
       collateral, roi_pct, breakeven, pop_pct, remark
FROM jstocksnp.jstockdata_reco_weekly_optionstrat
ORDER BY review_date DESC, strategy, scrip;
```

Keep richer bid/ask scenarios, sources, quote timestamps and performance assumptions in the dated local report. These records are recommendations, not executions or realized returns. Any later performance observations should be stored separately and linked by `reco_id`.

The top-level `option_type` column is omitted: derive P for CASH_SECURED_PUT and BULL_PUT_CREDIT_SPREAD, and C for BEAR_CALL_CREDIT_SPREAD. Retain option_type inside each legs_json entry; the importer validates it against strategy.
