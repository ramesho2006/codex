# Prompt log — Weekly Trend-Aligned Options Review

Session date: October 31, 2026 (America/Chicago). Exact message times were not available. User-authored prompts are recorded in conversation order; automatically supplied browser/environment metadata is omitted. HTML whitespace entities are normalized to spaces; wording and original numbering are retained. This is a user-prompt log, not a full assistant/tool transcript.

## 1. Check the browser connection

```text
I have logged into optionstrat.com  in the browser panel.
can you check the connection
```

## 2. Browser ready

```text
done
```

## 3. Original analysis request

```text
now,

(a) connect to MySQL 8.0,

(b) look at jstockdata_hatrend and jstockdata_hatrend_extend, jstockharecent and jstockdata_harecent_extend tables

(d) get the UP and DOWN  trending scrips

(e) use optionstrat optimize feature

(f) recommend the following:

1. suitable candidates for cash secured puts
2. suitable candidates for put credit spreads
3. suitable candidates for bear credit spreads

with maximum probablity of profit, minimum probability of loss and maximum profit , maximum roi%

list the candidates with suitable expiry dates 30 to 40 days DTE

40 to 50 delta for sell legs

20 to 30 delta for buy legs
```

## 4. Continue analysis

```text
continue
```

## 5. Preserve the workflow

```text
save this approach/analysis. give a suitable name.
we may want to use this every week
```

## 6. Log prompts and approach

```text
please log the prompts and save the review approach
```

## Interpretation and implementation notes

These notes document the assistant's interpretation, not additional user instructions:

- Named the workflow **Weekly Trend-Aligned Options Review**.
- Resolved `jstockharecent` to the existing `jstockdata_harecent` table.
- Interpreted “bear credit spreads” as bear call credit spreads.
- Interpreted delta bands as absolute option deltas: 0.40–0.50 sold and 0.20–0.30 bought.
- Used HA corrected candle color plus SMA direction for ongoing trends; weekly agreement was preferred. BUY/SELL transition events were not used as a substitute for ongoing trend.
- Kept probability, dollar profit, ROI and maximum loss as separate competing objectives.
- Preserved the original analysis; created a reusable skill and project workflow guide. No orders, database mutations or recurring schedule were authorized by these prompts or performed.

## Suggested prompt for future use

The following is a reusable prompt drafted from this session, not a historical user message:

```text
Run the Weekly Trend-Aligned Options Review for this week using the latest completed market session in MySQL 8.0 and my signed-in OptionStrat session. Screen daily UP/DOWN HA and SMA trends with weekly confirmation. Review cash-secured puts, bull put credit spreads and bear call credit spreads with 30–40 calendar DTE, absolute sell-leg delta 0.40–0.50 and buy-leg delta 0.20–0.30. Compare modeled probability of profit/loss, maximum profit/loss, full CSP collateral and ROI, with midpoint and bid/ask scenarios. Flag earnings, liquidity and conflicting signals. Save the prompts, dated report, full trend lists and verified strategy links; compare with the previous review. Do not place trades.
```

Related files: [review approach](../Weekly-Trend-Aligned-Options-Review.md), [original recommendations](recommendations.md), [full trend list](trend_screen.md).
