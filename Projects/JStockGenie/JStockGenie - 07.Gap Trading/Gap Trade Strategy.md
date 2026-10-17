# Gap Trade Strategy

**Status:** Strategy definition for review; paper trading only when implemented. No orders may be submitted from this document alone.

## Objective

Trade the expected move from a stock's opening gap back toward the previous session's close (gap fill). Start as an intraday strategy. If neither an exit nor the maximum holding period is reached, a position may remain open overnight for up to 10 trading sessions.

## Signal source and candidate rules

- Source: `jstocksnp.jstockview_gap_screener`.
- Use the view's `gap_pct` to qualify candidates by gap magnitude: 3% through 19%, inclusive (`3 <= ABS(gap_pct) <= 19`).
- Exclude gaps outside that range. A gap above 20% is treated as a possible split/corporate-action anomaly and must not be traded without independent corporate-action validation.
- Use the gap direction in the view to determine the trade side. Confirm the actual available column/value encoding before implementation.
- Recheck that the screener row and market data are current before placing an order.

## Direction

| Gap | Trade | Intended move |
|---|---|---|
| Gap up | Short sale | Price falls toward the prior close |
| Gap down | Long purchase | Price rises toward the prior close |

Short entries are allowed only when the broker reports the symbol is shortable and the account has the required permissions and buying power. Otherwise skip the candidate.

## Entry timing

- Evaluate eligible candidates 15 minutes after the regular U.S. market open: **9:45 a.m. ET / 8:45 a.m. CT**.
- Enter at that evaluation time if the candidate still qualifies and all account, price, data, and risk checks pass.
- No additional breakout, VWAP, or other price-confirmation condition has been specified.
- Exact entry order type and price protection remain to be chosen before implementation.

## Stops, targets, and position management

All percentage levels are measured from the actual average entry price.

| Rule | Long (gap down) | Short (gap up) |
|---|---:|---:|
| Stop loss, 1% adverse move | Entry × 0.99 | Entry × 1.01 |
| TP#1, 3% favorable move | Entry × 1.03 | Entry × 0.97 |
| TP#2, 5% favorable move | Entry × 1.05 | Entry × 0.95 |

- At TP#1, close 50% of the original position quantity (rounding down to a whole share; handle a one-share position without creating a zero-share exit).
- For the remaining shares, the stated alternatives are TP#2 at 5% or a 1% trailing stop activated after TP#1. The strategy owner must select whether to use TP#2, the trailing stop, or a defined combination before implementation.
- The prior close is the gap-fill objective. Treat reaching it as a profit exit for all remaining shares. If the prior close is reached before TP#1, exit the entire position there. If TP#1 has already been reached, exit the remaining position at the prior close.
- The 1% stop is based on price relative to entry. A stop trigger does not guarantee an execution at that price, particularly after an overnight gap.
- Keep stop/exit orders synchronized with the remaining position quantity after partial fills and partial profit-taking.

## Risk controls

- Maximum planned loss per trade: **1% of account equity**. Calculate share quantity from account equity and the distance between entry and stop; round down and skip if the minimum tradable quantity would exceed the cap.
- Maximum simultaneous positions: **10**. Count open positions and pending entry orders to avoid exceeding the limit.
- The original input also says “daily loss 1% each trade.” A separate account-wide daily loss cap is not defined yet. Do not infer a cumulative daily threshold; it must be specified before automation.
- Do not open a trade if account equity/buying power, market data, asset tradability, or short availability cannot be verified.

## Holding period and time-based exit

- Intended holding period begins as day trading; positions may carry overnight if no stop, target, or gap-fill exit occurs.
- Maximum holding period: 10 trading sessions, counting the entry session as session 1.
- At the end of session 10, close any remaining quantity with a market exit during regular trading hours. The precise cutoff time on that session remains to be selected.
- If the next session opens beyond the 1% stop level, exit at the first available regular-session opportunity; the realized loss may exceed 1% because the stop price cannot be guaranteed across a gap.

## Operating mode and audit

- Initial operating mode: Alpaca paper trading only. Live trading requires a separate deliberate configuration and review.
- Log each screener snapshot, qualifying/rejected rule, quote, order request, broker response, fill, stop/target update, and exit reason.
- Fail closed on stale or missing data, an unknown gap-direction encoding, duplicate/pending orders, broker rejections, or unavailable short inventory.

## Decisions required before implementation

1. Choose TP#2, a 1% trailing stop after TP#1, or a precise combination for the remaining half.
2. Define a cumulative daily loss limit (or explicitly decide there is none beyond per-trade limits).
3. Choose entry order type and price protection, including handling if the 9:45 entry is not filled.
4. Choose the session-10 exit cutoff time.
5. Confirm the view's exact `gap_pct` sign convention and gap-direction values, plus how prior close is obtained if it is not included in the view.
