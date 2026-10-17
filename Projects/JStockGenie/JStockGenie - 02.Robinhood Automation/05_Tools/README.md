# Tools

Helper scripts and generated builders live here.

## Agentic Trading Journal Builder

- `agentic_trade_journal_builder/build_agentic_journal.mjs`

This script rebuilds:

- `04_Journal/Agentic Trading Journal/Robinhood_MyAgentic_Trading_Journal.xlsx`

## Reco News Fetcher

- `reco_news_fetcher.py`

Fetches recent news for `jstockdata_scrips` rows where `RecoUniverseStatus = 'KEEP'` and `RecoUniverseRank <= 1000`, writes raw headlines to `jstockdata_reco_news_raw`, then runs `CALL reco_news_signal_refresh(days);`.

Configure one provider key before running:

```powershell
$env:FINNHUB_API_KEY = '...'
# or
$env:POLYGON_API_KEY = '...'
# or
$env:ALPHA_VANTAGE_API_KEY = '...'
```

Example:

```powershell
python 05_Tools\reco_news_fetcher.py --provider auto --days 7 --limit 1000
```

## Leveraged Dip Monitor

- `leveraged_dip_monitor.py`

Fetches current quotes for an enabled leveraged basket, compares them with the
latest EOD Java Trend close, applies Combined/LO/SMA and OptiTrend guardrails,
and writes review-only results to MySQL 8.

```powershell
python 05_Tools\leveraged_dip_monitor.py --basket SNP-ETF-LEVG
```

Use `--no-write` for a diagnostic run. The script requires `MYSQL80_URL` and
never places Robinhood orders.
