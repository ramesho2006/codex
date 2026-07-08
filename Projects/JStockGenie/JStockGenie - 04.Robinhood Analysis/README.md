# JStockGenie - 04. Robinhood Analysis

Date created: 2026-06-28

This folder is the Robinhood account analysis workspace for comparing Robinhood portfolio exposure against JStockGenie recommendations.

## Scope

- Review Robinhood account-level value, cash, buying power, equity exposure, and options exposure.
- Select one account at a time for detailed position analysis.
- Compare current holdings against JStockGenie recommendation outputs and basket routines.
- Produce analysis-only recommendations for manual review or a later approved automation workflow.

## Current Account Inventory

| Account | Type | Brokerage Type | Nickname | Default | Agentic Trade Access |
|---|---:|---|---|---:|---:|
| ending 0302 | cash | individual | My Trading | yes | no |
| ending 1224 | cash | individual | My Agentic | no | yes |
| ending 1512 | margin | individual | My Investments | no | no |
| ending 1832 | margin | individual, managed |  | no | no |
| ending 0097 | margin | ira_traditional |  | no | no |
| ending 9459 | cash | ira_roth |  | no | no |

## Important Guardrails

- Analysis can review any selected account.
- Agentic trade actions are available only for the `My Agentic` account ending `1224`.
- No live order should be placed without an explicit approval step.
- Options should remain manual unless a separate approved workflow is created.

## Starter Files

- `Robinhood_Portfolio_Snapshot_20260628.md`: account-level value and buying-power snapshot.
- `RUNBOOK.md`: repeatable workflow for Robinhood analysis.

