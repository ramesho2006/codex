# SQL

SQL files are split into migrations and reusable review queries.

## Migrations

- `migrations/20260704_weekly_target_recos.sql` - adds weekly target-band recommendations and updates the weekly wrapper.
- `migrations/20260705_momentum_signal.sql` - adds momentum signal table/routine and updates the weekly wrapper.
- `migrations/20260706_rename_momentum_signal_table.sql` - renames `jstockdata_momentum_signal` to `jstockdata_reco_momentum_signal`.
- `migrations/20260706_rename_reco_symbol_to_scrip.sql` - renames active reco table columns from `symbol` to `scrip`.
- `migrations/20260706_recent_table_indexes.sql` - adds recent trend indexes used by reco joins.
- `migrations/20260706_rename_weekly_master_refresh.sql` - renames the weekly wrapper to the canonical master routine.
- `migrations/20260706_add_reco_universe_status_to_scrips.sql` - adds `jstockdata_scrips.RecoUniverseStatus` and `RecoUniverseRank`.
- `migrations/20260706_apply_reco_universe_keep_filter.sql` - applies the KEEP and `RecoUniverseRank <= 1000` universe gate to active reco refresh routines.
- `migrations/20260707_universe_status_refresh.sql` - adds `reco_universe_status_refresh(p_keep_limit)` to rerank EQ/ETF scrips periodically.
- `migrations/20260707_news_signal.sql` - adds news raw/signal tables and `reco_news_signal_refresh(p_lookback_days)`.

## Queries

- `queries/weekly_target_recos_queries.sql` - review queries for EQT, ETF, and manual options target-band recommendations.

## Canonical Weekly Master Routine

```sql
CALL reco_weekly_master_refresh();
```

This is the only weekly master refresh routine. Do not create duplicate wrapper routines for the same sequence.

Recommendation refresh routines use `jstockdata_scrips.RecoUniverseStatus = 'KEEP'` and `RecoUniverseRank <= 1000` as the active EQ/ETF universe gate. `RecoUniverseRank` stores the numeric rank produced by `reco_universe_status_refresh(1000)`. Scrips marked `OMIT` or ranked above 1000 are excluded from trading analysis, momentum refresh, projection refresh, basket refresh, and target recommendation inputs.

Child routine sequence:

1. `reco_universe_status_refresh(1000)`
2. `reco_news_signal_refresh(7)`
3. `reco_backtest`
4. `reco_trade`
5. `reco_invest`
6. `reco_options`
7. `reco_projection_refresh`
8. `reco_projection_enrich_outputs`
9. `reco_momentum_refresh`
10. `reco_basket_refresh`
11. `reco_weekly_target_refresh`

News data is fetched outside SQL with `05_Tools/reco_news_fetcher.py`. The SQL master refresh only rescans already-fetched raw news and applies the latest signal overlay.

## Momentum Phase

`jstockdata_reco_momentum_signal.momentum_phase` classifies where each scrip is in its current momentum cycle:

| momentum_phase | Meaning |
|---|---|
| `EARLY` | Bullish momentum has recently started and acceleration is positive. |
| `BULLISH_ACCELERATING` | Bullish momentum is aligned across `Combined_Signal` and `LODeltaSignal`, not overextended, and acceleration is positive or neutral. |
| `BEARISH_ACCELERATING` | Bearish momentum is aligned across `Combined_Signal` and `LODeltaSignal`, not deeply oversold, and acceleration is negative or neutral. |
| `MATURE` | Bullish momentum exists, but the move may be extended by HARSI or rally age. |
| `WEAKENING` | Bullish score remains positive, but acceleration has turned negative. |
| `NEUTRAL` | Momentum score is mixed or below threshold. |
| `REVERSAL_RISK` | Momentum and supporting signals conflict or no longer fit a clean trend. |

Weekly EQT/ETF picks should generally prefer `momentum_direction = 'BULLISH'` and `momentum_phase IN ('EARLY', 'BULLISH_ACCELERATING')`.
