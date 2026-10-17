# Iron Condor screen — September 30, 2026

Source: `MYSQL80_URL`, database `jstocksnp`.

Query filters: `dte <= 10` and `collateral <= 500`.

| Symbol | Expiration | DTE | Put spread | Call spread | Lower / upper breakeven | Max profit | Max loss | Collateral | ROR | POP |
|---|---:|---:|---|---|---:|---:|---:|---:|---:|---:|
| XLK | 2026-10-09 | 8 | short 186 / long 181 | short 210 / long 215 | 185.41 / 210.60 | $59.50 | $440.50 | $500 | 13.51% | 71.27% |
| EEM | 2026-10-02 | 1 | short 64 / long 62 | short 72 / long 74 | 63.98 / 72.03 | $2.50 | $197.50 | $200 | 1.27% | 98.74% |
| XLI | 2026-10-02 | 1 | short 161 / long 156 | short 188 / long 193 | 160.95 / 188.05 | $5.00 | $495.00 | $500 | 1.01% | 86.01% |

Execution results: XLK Oct 9 (long 181 put, short 186 put, short 210 call, long 215 call) was submitted to MyPaperTradeBOT at a $1.11 credit, but Option Alpha later marked the trade **canceled**. It therefore does not appear in Open Positions. The earlier position-details view showed it as opening/working before the cancellation was finalized.

EEM Oct 2 (long 62 put, short 64 put, short 72 call, long 74 call) was rejected by Option Alpha's pricing-anomaly check on both the initial submission and retry. The log reported short-leg mid $0.05 versus long-leg mid $0.06. No EEM position was created and no position note could be added.

XLI Oct 2 (long 156 put, short 161 put, short 188 call, long 193 call) was rejected by Option Alpha's pricing-anomaly check. The log reported short-leg mid $0.11 versus long-leg mid $0.11. No XLI position was created and no position note could be added.

Replacement quotes reviewed October 1, 2026: XLK Oct 9 iron condor $0.47; EEM Oct 9 64/62 short put spread $0.38; EWY Oct 9 177/172 short put spread $0.82.

After confirmation, all three replacement paper orders were submitted to MyPaperTradeBOT, but Option Alpha subsequently canceled each one because it was unable to fill at the requested price: XLK at $0.47 credit, EEM at $0.38 credit, and EWY at $0.82 credit. The canceled-position detail states: `Position canceled. Unable to fill trade at requested price.` The note `Codex Paper Trade order` remains saved on each canceled record.
