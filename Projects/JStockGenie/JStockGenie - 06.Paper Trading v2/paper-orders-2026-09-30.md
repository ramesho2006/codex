# Option Alpha paper order results — September 30, 2026

Account: Paper Trading; bot: MyPaperTradeBOT.
User authorized one-contract attempts for the four SQL screener results.
Every ticket used Short Put Spread, buying the lower-strike put and selling the higher-strike put at the same expiration.
Minimum credits were rounded upward to whole cents from the database's estimated credits. SmartPricing: Normal. Exit options: None.

| Symbol | Expiration | Short put | Long put | Contracts requested | Minimum credit/share | Final verified outcome |
|---|---|---:|---:|---:|---:|---|
| XLK | 2026-10-09 | 186 | 181 | 1 | $0.26 | Filled; $38 total credit, $462 capital at risk. Opened at 7:51 PM in Option Alpha's displayed timezone. |
| EWY | 2026-10-02 | 177 | 172 | 1 | $0.75 | Rejected before opening: pricing anomaly. Short put midpoint $1.01 was below long put midpoint $1.26. |
| EWY | 2026-10-09 | 177 | 172 | 1 | $1.19 | Submitted, then canceled by platform for trade timeout; unable to fill at requested price. Zero contracts. |
| EEM | 2026-10-09 | 64 | 62 | 1 | $0.19 | Submitted, then canceled by platform for trade timeout; unable to fill at requested price. Zero contracts. |

Verification: Option Alpha position details and automation logs. Market indicator showed closed, but the paper simulator accepted submissions and filled XLK. No real-money orders were placed. No retries or recurring automation were configured. Do not duplicate the filled XLK position on a later retry.

## Notes update
Saved and verified the exact note "Codex Paper Trade order" on the XLK October 9 filled position, EWY October 9 canceled position, and EEM October 9 canceled position. The EWY October 2 attempt was rejected before a position record was created; its automation log has no position notes field.

## Cancellation verification
Reopened both October 9 canceled position records. Both show: Position canceled. Unable to fill trade at requested price. Trades status: Trade timeout. EWY requested credit 1.19; displayed working-order midpoint 1.09; submitted 7:55 PM, canceled 7:57 PM. EEM requested credit 0.19; displayed working-order midpoint 0.17; submitted 7:57 PM, canceled 7:59 PM. Times are as displayed in Option Alpha. Both show zero contracts and zero credit received. Limits were based on SQL estimated credits rounded upward to cents; displayed quote midpoints were lower. No retries were made.

## User-authorized October 9 retries
EEM 64/62 puts: one contract, Normal SmartPricing 0.18 to 0.17 minimum credit. Submitted Sep 30 at 8:15 PM platform time; canceled at 8:17 PM for Trade timeout, unable to fill at requested price; zero contracts. Saved and verified note: Codex Paper Trade order.
EWY 177/172 puts: one contract, 1.09 minimum credit. Submitted Sep 30 at 8:17 PM platform time and filled at 1.09 ( total credit), maximum loss  before fees. Saved and verified note: Codex Paper Trade order.
October 2 attempt left unchanged per user instruction. XLK was not duplicated. No further retries were submitted.

## Possible next session retry
User suggested possibly retrying the EEM October 9 64/62 put spread during market hours tomorrow, October 1, 2026. EEM remains unfilled. No scheduled retry or automatic order was created from this tentative plan. Recheck quotes and existing positions before any future attempt.
