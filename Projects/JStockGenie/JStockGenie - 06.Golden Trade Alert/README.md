# JStockGenie - 06.Golden Trade Alert

This folder stores the dedicated Golden Trade Alert log for `My Agentic`.

## Golden Trade Rule

- `+3%` profit target is for the full `My Agentic` basket level.
- `-1%` stop loss is for each individual position only.
- If any one position hits `-1%`, prepare an exit review for that position.
- If the full basket hits `+3%`, prepare full basket profit booking.

## Alert Log

Use `JStockGenie - 06 Golden Trade Alert.csv` to record:

- Golden Trade Alert snapshots and triggers.
- Alert timing in Central Time using `alert_timestamp_ct` and `last_updated_ct`.
- Recommended Golden Trade Action.
- User confirmation status.
- Robinhood order ids after orders are placed.
- Fill status, filled price, filled quantity, and realized P/L after execution.

Do not place trades automatically from alert checks. Real Robinhood orders require explicit user confirmation.

For August 17, 2026, the user already checked and placed a manual order in the morning. Continue Golden Trade Alert checks from 12:30 PM CT onward.
