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
- `migrations/20260714_predictive_direction.sql` - adds major pivot history, latest predictive direction, `weekly_verdict`, and `reco_predictive_direction_refresh()`.
- `migrations/20260726_quant_score_refresh.sql` - renames `jstockdata_reco_universe_score` to `jstockdata_reco_quant_score` and refines the universe rank into a JStockGenie Quant-style score.
- `migrations/20260727_current_positions_quant_score.sql` - adds `quant_score` to `jstockdata_current_positions` for current-position review snapshots.
- `migrations/20260727_current_positions_analysis_date_end.sql` - moves `jstockdata_current_positions.analysis_date` to the end of the table layout.
- `migrations/20261006_leveraged_dip_monitor.sql` - adds leveraged-basket dip
  configuration, live quote snapshots, and review-only monitor logs.

## Queries

- `queries/weekly_target_recos_queries.sql` - review queries for EQT, ETF, and manual options target-band recommendations.

## Canonical Weekly Master Routine

```sql
CALL reco_weekly_master_refresh();
```

This is the only weekly master refresh routine. Do not create duplicate wrapper routines for the same sequence.

Recommendation refresh routines use `jstockdata_scrips.RecoUniverseStatus = 'KEEP'` and `RecoUniverseRank <= 1000` as the active EQ/ETF universe gate. `RecoUniverseRank` stores the numeric rank produced by `reco_universe_status_refresh(1000)` and recorded in `jstockdata_reco_quant_score`. Scrips marked `OMIT` or ranked above 1000 are excluded from trading analysis, momentum refresh, projection refresh, and target recommendation inputs.

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
10. `reco_predictive_direction_refresh`
11. `reco_weekly_target_refresh`

News data is fetched outside SQL with `05_Tools/reco_news_fetcher.py`. The SQL master refresh only rescans already-fetched raw news and applies the latest signal overlay.

## JStockGenie Quant Score

`jstockdata_reco_quant_score` is the canonical Quant-style score table. It is not a clone of Seeking Alpha's proprietary Quant Rating, but it uses the same spirit of a multi-factor composite. The available JStockGenie factors are:

| Component | Purpose |
|---|---|
| `trend_score` | Daily/weekly Combined Signal, LO Delta, SMA Delta, and HARSI alignment. |
| `momentum_score` | Heikin Ashi trend/momentum strength and rally slope/angle. |
| `projection_score` | Expected return, upward/downward probability, risk/reward, and projection confidence. |
| `backtest_score` | Historical win rate, average trade return, worst trade, and sample depth. |
| `quality_score` | Source rank and liquidity/dollar-volume proxy for size and tradability. |
| `news_score` | Recent headline sentiment/catalyst support minus risk-event pressure. |
| `liquidity_score` | Dollar-volume tradability support. |

Use `quant_star_rating` and `quant_analysis_rating` as the closest local analog to a Seeking Alpha Quant Rating:

| `quant_analysis_rating` | Score Range |
|---|---|
| `STRONG_BUY` | `quant_score >= 85` |
| `BUY` | `72 <= quant_score < 85` |
| `HOLD` | `55 <= quant_score < 72` |
| `SELL` | `40 <= quant_score < 55` |
| `STRONG_SELL` | `quant_score < 40` |

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

## Predictive Direction Review

Latest screener direction:

```sql
SELECT scrip, expected_direction, direction_probability_pct,
       direction_confidence_pct, weekly_verdict,
       daily_combined_signal, weekly_combined_signal,
       daily_momentum_direction, daily_momentum_confidence_pct,
       weekly_momentum_direction, weekly_momentum_confidence_pct
FROM jstockdata_reco_predictive_direction
WHERE reco_universe_status = 'KEEP'
ORDER BY direction_confidence_pct DESC, direction_probability_pct DESC;
```

Scrip pivot history:

```sql
SELECT pivot_type, pivot_date, pivot_close, move_from_prev_pct,
       move_to_next_pct, daily_combined_signal, weekly_combined_signal
FROM jstockdata_reco_major_pivots
WHERE scrip = 'MSFT'
ORDER BY pivot_date;
```
