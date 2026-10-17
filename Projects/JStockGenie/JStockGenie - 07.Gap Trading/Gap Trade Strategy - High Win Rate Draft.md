# Gap Trade Strategy — High-Win-Rate Draft

**Status:** Research proposal only. These rules are hypotheses for a new backtest and paper-trading evaluation; a 70% profitable-trade rate is a target, not a guarantee. Do not use for live orders without validation.

## Objective and definition of success

Fade an opening gap toward the prior session close, while prioritizing a high probability of a net-profitable completed trade. A “win” means the final realized P&L is positive after estimated spread, slippage, borrow costs, and fees. A touch of a gap-fill level by itself is not a win.

## Candidate selection by opening-gap size

Use `jstocksnp.jstockview_gap_screener` and its `gap_pct`, `gap_direction`, `prior_close`, and current price/quote data. Confirm the view’s sign convention at runtime. Gap up → short; gap down → long.

| Absolute gap | Rule | Historical 10-session touch rates in the current database* |
|---|---|---|
| 3–5% | Primary cohort. Eligible after all filters and reversal confirmation. First target: 50% gap retracement. | 50% retracement: 78.8% up gaps / 84.1% down gaps; full fill: 63.5% / 70.4%. |
| 5–10% | Selective cohort. Trade only with a clear reversal, no material catalyst, and enough reward remaining after confirmation. First target: 25% gap retracement. | 25% retracement: 87.5% up / 85.2% down; full fill: 48.5% / 52.1%. |
| 10–19% | Exclude from automatic trading initially; keep as a separately tracked paper cohort. Only test in paper at half risk (0.125% account equity), after strong reversal confirmation, targeting 25% retracement. | 25% retracement: 73.9% up / 69.3% down; full fill: 23.1% / 24.1%. |

\* Daily-bar proxy: 11,398 fully observed gap records, with up to 10 daily bars beginning on the gap date. It does not establish that the target was reached after a confirmed entry or before a stop. Results are specific to this database and period.

## Reject candidates before entry

- Skip a gap if the opening move is caused by earnings, guidance, a merger/buyout, FDA or legal news, a major analyst action, or another material company-specific event. These can be continuation/breakaway gaps rather than ordinary fades.
- Skip suspected splits, symbol changes, stale screener rows, halted/uncrossed markets, or symbols without reliable quotes.
- Require price above $10, 20-session average dollar volume above $20 million, and a live bid/ask spread no wider than 0.15% of midpoint. These are starting liquidity filters and should be tuned only on training data.
- For shorts, verify current shortability/borrow availability and estimated borrow cost before entry; otherwise skip.
- Require at least 1.0R of remaining reward to the first target after the proposed stop. If the gap has already retraced through the target, skip.

## Reversal confirmation and entry

Use the first 30 minutes to define the opening range. Do not enter solely because `gap_pct` qualifies.

- **Gap up / short:** after the first 30 minutes, require a lower high or failed retest near VWAP, followed by a 5-minute close below VWAP and a break of the opening-range low. Enter on the break or a failed retest of VWAP/opening-range low.
- **Gap down / long:** require a higher low or failed retest near VWAP, followed by a 5-minute close above VWAP and a break of the opening-range high. Enter on the break or a successful retest.
- Cancel the setup if price resumes strongly in the gap direction, the gap is already filled before the trigger, or the first-target reward is less than the stop distance.
- Use a marketable limit order with a maximum slippage bound; if not filled promptly, cancel and reassess rather than chase.

## Stop and risk

- Do not use a fixed 1% price stop. Set a structural stop beyond the reversal setup: above the opening-range/reversal swing high for shorts, below the opening-range/reversal swing low for longs, with a small volatility buffer (initial research setting: 0.1 × ATR(14)).
- Size shares so the planned loss at that stop is at most **0.25% of account equity per trade** during paper evaluation. If the stop is too wide or size is below one share, skip. This is a conservative starting test setting, not a claim that the stop is optimal.
- Cap simultaneous positions at 10 and cap combined planned open risk at 2% of equity. Stop opening new positions for the day after a 1% account-equity loss. These are portfolio controls; the historic single-trade proxy did not model them.
- If the market opens beyond the stop, exit at the first executable price and record the realized gap loss. Stop prices do not guarantee fills.

## Profit-taking

Define gap progress from the actual entry toward the prior close:

`progress = (favorable price move from entry) / (entry-to-prior-close distance)`

- At the cohort’s first target (50% progress for 3–5%; 25% for 5–10% and experimental 10–19%), close **70%** of the initial position.
- For the remaining 30%, set a limit at the prior close. After the first target fills, trail the remainder behind the most recent completed daily swing low (long) or swing high (short), with a volatility buffer. Recalculate at each session close and keep a protective order in place for the next session. If the trailing stop triggers, exit; if the prior close is reached, exit the remainder. Do not widen a stop after entry.
- If the price closes back in the gap direction beyond the reversal structure before the first target, exit rather than wait for the original stop.
- Use OCO/bracket-style order handling where supported, and reconcile partial fills so exit quantity never exceeds the remaining position.

## Carry-forward and time exit

- Allow overnight holds only while the original reversal thesis remains intact. Re-evaluate the position at each regular-session close.
- If the gap has made no progress toward the first target after 3 sessions, reduce or close the position; test both choices separately rather than choosing after seeing results.
- Maximum hold: 10 trading sessions, counting entry day as session 1. Exit remaining shares during the regular session on session 10; define the exact cutoff before implementation.
- On an overnight open through a stop or after invalidating news, exit at the first executable opportunity. Do not assume a stop limits the loss to the planned amount.

## Validation plan and acceptance criteria

1. Rebuild the test with 1-minute or 5-minute data so the entry, VWAP/opening-range confirmation, stop, and target sequencing are observable. Daily OHLC is insufficient for this ruleset.
2. Test each gap-size cohort separately, with up/down splits, costs, slippage, short-borrow constraints, delisted symbols where available, and realistic partial fills.
3. Enforce the 10-position cap and portfolio risk limits with a predeclared ranking rule. Use chronological train/validation/out-of-sample periods; do not tune on the final holdout.
4. Treat 70% as achieved only if **net profitable completed trades** are at least 70% out of sample, expectancy remains positive after costs, profit factor is above 1.2, and drawdown stays within the chosen risk limit. Report confidence intervals and sample count; do not claim 70% from raw target-touch frequency.
5. Paper trade the frozen rules for at least 100 completed trades per eligible cohort, or longer if needed for meaningful confidence intervals. Change one rule at a time and rerun the holdout.

## Why the targets differ by cohort

In this database, within 10 daily sessions, the full gap was touched in 58.1% of all 3–19% gaps. The 25% retracement was touched more often: 91.0–91.4% for 3–5% gaps, 85.2–87.5% for 5–10%, and 69.3–73.9% for 10–19%. This motivates closer first targets and excluding large gaps from automatic fades. These are price-touch rates, not the probability that the proposed confirmed-entry/stop strategy wins.

## References

- [Current stock gap-fill data and methodology](https://swingtradebot.com/stock-gap-lab)
- [Research on opening price gaps and strategies](https://pmc.ncbi.nlm.nih.gov/articles/PMC10017064/)
