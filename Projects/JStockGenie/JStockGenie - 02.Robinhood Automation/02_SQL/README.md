# SQL

SQL files are split into migrations and reusable review queries.

## Migrations

- `migrations/20260704_weekly_target_recos.sql` - adds weekly target-band recommendations and updates the weekly wrapper.
- `migrations/20260705_momentum_signal.sql` - adds momentum signal table/routine and updates the weekly wrapper.

## Queries

- `queries/weekly_target_recos_queries.sql` - review queries for EQT, ETF, and manual options target-band recommendations.

## Primary Weekly Wrapper

```sql
CALL reco_weekly_projection_refresh();
```

Current sequence:

1. `reco_backtest`
2. `reco_trade`
3. `reco_invest`
4. `reco_options`
5. `reco_projection_refresh`
6. `reco_projection_enrich_outputs`
7. `reco_momentum_refresh`
8. `reco_basket_refresh`
9. `reco_weekly_target_refresh`
