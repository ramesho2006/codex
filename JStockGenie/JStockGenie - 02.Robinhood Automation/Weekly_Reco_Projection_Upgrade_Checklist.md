# Weekly Reco Projection Upgrade Checklist

Created: 2026-06-23

Use this after Friday EOD data load and Java trend model completion.

## 1. Reco Routines To Run Weekly

The Java Trend model now runs this wrapper automatically through `JStockDataRunRecommendations(true)`:

```sql
CALL reco_weekly_projection_refresh();
```

It runs:

1. reco_backtest
2. reco_trade
3. reco_invest
4. reco_options
5. reco_projection_refresh
6. reco_projection_enrich_outputs
7. reco_basket_refresh

The wrapper refreshes projection fields in:

- jstockdata_reco_backtest
- jstockdata_reco_trade
- jstockdata_reco_invest
- jstockdata_reco_options

Manual SQL use is only needed for troubleshooting or ad hoc refreshes. The normal weekly process should be Java-driven.

## 1A. Weekly Java Flow

After EOD data upload, run the Java Trend model. The Trend/Reco Java path now includes:

1. Trend CSV generation/import
2. Summary import
3. `CALL reco_weekly_projection_refresh()`
4. Yahoo options premium enrichment
5. Updated `jstockdata_reco_*` tables

Projection source table:

- jstockdata_reco_projection

## 2. Weekly Basket Routines

Short-term swing, days to a few weeks:

- perform Weekly EQT Basket Routine
- use jstockdata_reco_trade
- prioritize 5 to 20 trading-day projection horizons
- prefer high upward_probability_pct, strong expected_return_pct, favorable risk_reward_ratio, and acceptable downward_projection_pct

Longer-term investment, weeks to a few months:

- perform Weekly ETF Basket Routine
- use ETF common-holding overlap plus JStockGenie projection fields
- prioritize 4 to 16 week projection horizons
- prefer higher projection_confidence_score and lower downward_probability_pct

## 3. Robinhood Agentic Account Trade Automation

Target account:

- My Agentic, ending 1224

Weekly process:

1. Pull buying power, current positions, and open orders.
2. Compare current positions with Weekly EQT Basket Routine target basket.
3. Prepare SELL candidates first:
   - no longer in target basket
   - weak daily/weekly signals
   - poor projection confidence
   - downside projection exceeds tolerance
4. Prepare BUY candidates from highest-ranked EQT basket names.
5. Check Robinhood tradability.
6. Review each order.
7. Place real orders only after explicit user confirmation.
8. Update:
   - current positions CSV
   - proposed trades CSV
   - weekly trade journal
   - weekly summary

## 4. Manual Investing Steps For Other Robinhood Accounts

Use analysis only. Do not automate trades for non-Agentic accounts.

Weekly process:

1. Review existing positions by account.
2. Compare holdings with Weekly ETF Basket Routine output.
3. For long-term accounts, prefer gradual rebalancing:
   - keep core ETF exposure
   - add names with strong upward projection and lower downside probability
   - trim names with weak projection or deteriorating weekly trend
4. For retirement accounts, avoid short-term churn unless signals strongly deteriorate.
5. Manually place trades in Robinhood after reviewing tax, options, and account-specific constraints.

## 5. New Projection Fields

Common reco fields:

- trading_horizon_days
- trading_horizon_weeks
- upward_projection_pct
- upward_probability_pct
- downward_projection_pct
- downward_probability_pct
- expected_return_pct
- risk_reward_ratio
- projection_sample_size
- projection_confidence_score

Options-specific fields:

- underlying_trading_horizon_days
- underlying_upward_projection_pct
- underlying_upward_probability_pct
- underlying_downward_projection_pct
- underlying_downward_probability_pct
- expected_underlying_move_pct
- underlying_projection_confidence_score
- underlying_projection_sample_size

## 6. Validation Query

```sql
SELECT COUNT(*) FROM jstockdata_reco_projection;

SELECT COUNT(*), SUM(upward_projection_pct IS NOT NULL)
FROM jstockdata_reco_trade;

SELECT COUNT(*), SUM(underlying_upward_projection_pct IS NOT NULL)
FROM jstockdata_reco_options;
```
