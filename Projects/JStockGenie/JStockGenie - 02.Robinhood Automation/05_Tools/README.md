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
