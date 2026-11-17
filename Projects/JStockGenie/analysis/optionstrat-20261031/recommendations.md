# Options candidate review — October 31, 2026

MySQL connection verified: 8.0.26, database jstocksnp. Read-only queries only.

Reviewed jstockdata_hatrend, jstockdata_hatrend_extend, jstockdata_harecent and jstockdata_harecent_extend. The requested name jstockharecent does not exist; the recent table is jstockdata_harecent. Frequency values in the HA tables contain a trailing carriage return, removed for joins.

Latest daily session: October 30, 2026. 674 current daily symbols; 333 have GREEN HA corrected candles and UP SMA trend, 243 have RED candles and DOWN SMA trend, and 98 are mixed/other. Weekly confirmation reduces these to 292 UP and 192 DOWN. All 674 current recent rows matched historical rows on close, HA corrected color and SMA trend. Two older daily records were excluded. BUY/SELL event signals were not substituted for ongoing candle direction. Opti_ChancePct was not treated as option probability of profit.

The complete underlying screen is in trend_screen.md and trend_screen.json. This is a focused options shortlist, not an exhaustive optimization of every strike across all 576 trend-aligned symbols.

## Expiry and method

All shortlisted contracts expire December 4, 2026: 34 calendar days from October 31 (32 from Monday November 2). OptionStrat displayed 35d, consistent with its prior-session reference date of October 30. The requested 30–40 DTE window from October 31 spans November 30 through December 10. December 4 was available for all four shortlisted symbols.

Used the signed-in OptionStrat optimizer for CMCSA, PFE, XOM, SPY and QQQ. Started with its balanced return/probability results, then adjusted legs in its builder to enforce absolute option delta of 0.40–0.50 for sold contracts and 0.20–0.30 for purchased contracts. QQQ maximum-chance optimization produced an 810/850 call spread showing 98% chance and approximately 0.3% return; that is not a verified delta-compliant alternative and was not included. The optimizer does not establish a single simultaneous maximum for probability, dollars and ROI.

Quotes were observed October 31, a Saturday; these are displayed market snapshots, not guaranteed executable Monday prices. Prices, Greeks and probabilities must be refreshed before entry. Builder midpoint results differ from optimizer bid/ask-oriented results. No commissions or slippage are included.

## Delta-compliant shortlist

All amounts are USD per one-lot position, standard 100-share multiplier. P = put, C = call. Delta figures below are absolute option deltas, not signed position deltas. PoP is OptionStrat's displayed modeled chance of profit; approximate PoL = 100% minus rounded PoP, not probability of maximum loss.

| Strategy | Symbol | Sell | Buy | Sell / buy delta | Midpoint credit = max profit | Max loss | Full cash collateral (CSP) | PoP / approximate PoL | ROI |
|---|---|---|---|---|---:|---:|---:|---|---:|
| Cash-secured put | PFE | 30P | — | 0.401 / — | $92 | $2,908 | $3,000 | 71% / 29% | 3.07% |
| Cash-secured put | XOM | 185P | — | 0.419 / — | $600 | $17,900 | $18,500 | 69% / 31% | 3.24% |
| Bull put credit spread | PFE | 30P | 29P | 0.401 / 0.276 | $38 | $62 | — | 63% / 37% | 61.29% |
| Bull put credit spread | XOM | 185P | 175P | 0.419 / 0.226 | $337.50 | $662.50 | — | 63% / 37% | 50.94% |
| Bear call credit spread | SPY | 766C | 778C | 0.429 / 0.284 | $527 | $673 | — | 66% / 34% | 78.31% |
| Bear call credit spread | QQQ | 705C | 724C | 0.424 / 0.271 | $748.50 | $1,151.50 | — | 66% / 34% | 65.00% |

CSP ROI = credit / (short strike × 100). Spread ROI = credit / maximum loss. These are holding-period maximum returns, not expected or annualized returns. Higher position quantity scales profit and loss; it does not improve ROI or PoP. A cash-secured put is appropriate only if willing and able to buy 100 shares per contract at the strike. Short-put builder links below model identical option payoff; ignore their margin collateral when using a CSP and reserve the full cash shown above.

## Conservative quoted-side comparison

Sell at displayed bid; buy hedge at displayed ask. These are quote-based reference calculations, not promised fills. Midpoint PoP above does not apply exactly to these lower credits.

| Strategy | Credit / max profit | Max loss | ROI | Breakeven |
|---|---:|---:|---:|---:|
| PFE 30P CSP | $83 | $2,917 | 2.77% | $29.17 |
| XOM 185P CSP | $550 | $17,950 | 2.97% | $179.50 |
| PFE 30/29 put spread | $23 | $77 | 29.87% | $29.77 |
| XOM 185/175 put spread | $250 | $750 | 33.33% | $182.50 |
| SPY 766/778 call spread | $517 | $683 | 75.70% | $771.17 |
| QQQ 705/724 call spread | $719 | $1,181 | 60.88% | $712.19 |

## Liquidity evidence

| Contract, Dec 4 | Bid | Ask | Volume | Open interest | Absolute delta |
|---|---:|---:|---:|---:|---:|
| PFE 30P | 0.83 | 1.01 | 41 | 24 | 0.401 |
| PFE 29P | 0.48 | 0.60 | 4 | 39 | 0.276 |
| XOM 185P | 5.50 | 6.50 | 13 | 4 | 0.419 |
| XOM 175P | 2.25 | 3.00 | 112 | 32 | 0.226 |
| SPY 766C | 10.68 | 10.79 | 118 | 25 | 0.429 |
| SPY 778C | 5.42 | 5.51 | 118 | 268 | 0.284 |
| QQQ 705C | 14.78 | 15.10 | 678 | 289 | 0.424 |
| QQQ 724C | 7.32 | 7.59 | 147 | 64 | 0.271 |

CMCSA 23P met sell delta at 0.428 and displayed 66% PoP, but bid/ask was $0.50/$0.96, volume 22 and OI 1. Excluded from preferred candidates for poor liquidity. Its optimizer's 21P had delta 0.195 and did not meet the sell-delta requirement.

## Recommendation and qualifications

- Bear call spreads: QQQ is the preferred liquidity candidate among those checked; SPY offers higher quoted ROI and lower dollar maximum loss. Both have matching daily/weekly DOWN trends. Their exposure overlaps substantially, so they should not be viewed as independent diversification. Very low HA RSI readings (QQQ 8.41; SPY 9.34) flag rebound risk.
- Cash-secured puts: XOM is the preferred post-earnings watchlist candidate, with higher dollar premium and slightly higher collateral ROI than PFE. Its short contract's OI of 4 and wide spread make entry conditional on improved executable quotes. PFE has higher modeled PoP and much lower capital requirement, but earnings on November 3 make it unsuitable as the lower-event-risk choice before the report.
- Bull put spreads: XOM is the preferred conditional post-earnings candidate. PFE's higher midpoint ROI falls sharply at bid/ask and comes with earnings risk; reassess after November 3 instead of treating it as a low-risk income trade.
- Neither bullish candidate is an unconditional minimum-risk recommendation at these quotes. XOM HA RSI is 90.21 and PFE 87.69, so the UP trends are extended. Trend agreement does not calibrate option PoP or eliminate reversal risk.
- Defined-risk spread figures describe expiration payoff with both legs intact. Early assignment can create stock/cash obligations and temporary exposure. Close or manage spreads before expiration if unable to handle assignment. PoP is a model estimate, not a guarantee, and probability of loss is not its severity.

## Sources and reproducible strategy links

- [PFE 30P payoff](https://optionstrat.com/build/short-put/PFE/-.PFE261204P30)
- [XOM 185P payoff](https://optionstrat.com/build/short-put/XOM/-.XOM261204P185)
- [PFE 30/29 bull put spread](https://optionstrat.com/build/bull-put-spread/PFE/.PFE261204P29,-.PFE261204P30)
- [XOM 185/175 bull put spread](https://optionstrat.com/build/bull-put-spread/XOM/.XOM261204P175,-.XOM261204P185)
- [SPY 766/778 bear call spread](https://optionstrat.com/build/bear-call-spread/SPY/.SPY261204C778,-.SPY261204C766)
- [QQQ 705/724 bear call spread](https://optionstrat.com/build/bear-call-spread/QQQ/.QQQ261204C724,-.QQQ261204C705)
- [Pfizer November 3 earnings announcement](https://www.pfizer.com/news/press-release/press-release-detail/pfizer-invites-public-view-and-listen-webcast-november-3)
- [Exxon October 30 results](https://investor.exxonmobil.com/company-information/press-releases/detail/1213/exxonmobil-announces-third-quarter-2026-results)

No orders were placed, no trades saved to the account, and no database records changed.
