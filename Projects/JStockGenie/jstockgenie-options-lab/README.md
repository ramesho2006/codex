# JStockGenie Options Lab

Local, read-only options research UI for the JStockGenie strong bullish and bearish shortlist.

## Run

```powershell
.\start-options-lab.ps1
```

Open <http://localhost:4173>.

The server fetches US equity and ETF option chains from Tradier using `TRADIER_ENV`, `TRADIER_API_TOKEN`, and `TRADIER_SANDBOX_API_TOKEN` Windows User variables. Scans support configurable Min and Max DTE filters, with Max DTE capped at 120 days. It stores each successful symbol/DTE-range response in `data\tradier-options-cache.json` for 24 hours. Repeated Scan clicks reuse the local cache; enable **Force refresh** to bypass it. Enable **Refresh scrips from SQL** to rebuild the shortlist from the MySQL strong-buy/strong-sell screeners before fetching option chains. Sell premiums use the displayed bid multiplied by the returned contract size; zero-bid rows are excluded. POP is an implied-volatility, lognormal estimate and is not a broker guarantee. Production Tradier data is the default; sandbox is delayed and intended for testing. The UI reports unavailable chains instead of fabricating rows. It does not submit orders. The GuacTracker layout is only a workflow reference; this app has no GuacTracker dependency.

The launcher enables Node's system CA store so the local Windows certificate chain is used for HTTPS verification. Do not disable TLS verification.

Each result has a **Paper order** button. The order dialog previews and, after explicit confirmation, submits only one-contract day limit orders to Tradier Sandbox using `TRADIER_SANDBOX_API_TOKEN` and `TRADIER_SANDBOX_ACCOUNT`. Live order routes are intentionally not implemented. Tradier must approve the Sandbox account's options level before option previews or orders can be accepted.
