# Weekly Trading Operations Checklist

Updated: 2026-06-24

## Weekly Sequence

1. EOD data upload
2. Java Trend model
3. Check SQL `jstockdata_reco_*` tables
4. Approve and automate Robinhood Agentic trades
5. Execute manual trades on other Robinhood accounts

## 1. EOD Data Upload

- Upload the latest Friday EOD data.
- Confirm raw data is available before running Java.

## 2. Java Trend Model

Run the Java Trend model as usual.

The Java reco path now includes:

```sql
CALL reco_weekly_projection_refresh();
```

That wrapper runs:

- `reco_backtest`
- `reco_trade`
- `reco_invest`
- `reco_options`
- `reco_projection_refresh`
- `reco_projection_enrich_outputs`
- `reco_basket_refresh`

Java then runs Yahoo options premium enrichment.

## 3. Check SQL Tables

Check these after Java completes:

- `jstockdata_reco_backtest`
- `jstockdata_reco_trade`
- `jstockdata_reco_invest`
- `jstockdata_reco_options`
- `jstockdata_reco_projection`
- `jstockdata_reco_basket_current`
- `jstockdata_reco_basket_actions`

Quick validation:

```sql
SELECT COUNT(*) FROM jstockdata_reco_projection;
SELECT COUNT(*), SUM(upward_projection_pct IS NOT NULL) FROM jstockdata_reco_trade;
SELECT COUNT(*), SUM(underlying_upward_projection_pct IS NOT NULL) FROM jstockdata_reco_options;
```

## 4. Robinhood Agentic Automation

Use:

- Weekly EQT Basket Routine

Purpose:

- short-term swing trades, days to a few weeks

Steps:

1. Compare Agentic current positions with the latest EQT basket.
2. Prepare SELL candidates first.
3. Prepare BUY candidates from the strongest projected swing names.
4. Check Robinhood tradability.
5. Review orders.
6. Place orders only after explicit approval.
7. Update current positions, proposed trades, weekly journal, and weekly summary.

## 5. Manual Trades For Other Robinhood Accounts

Use:

- Weekly ETF Basket Routine

Purpose:

- longer-term investments, weeks to a few months

Steps:

1. Review account positions manually.
2. Compare holdings to the ETF growth/dividend baskets.
3. Use projection fields for conviction:
   - `upward_probability_pct`
   - `upward_projection_pct`
   - `downward_probability_pct`
   - `downward_projection_pct`
   - `risk_reward_ratio`
   - `projection_confidence_score`
4. Place trades manually in Robinhood.

## Notes

- Agentic account can be automated after explicit approval.
- Other accounts are analysis/manual execution only.
- `AABAZZ` remains ignored in reporting and activity.
