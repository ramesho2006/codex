"""
Fetch recent news for the active JStockGenie reco universe.

Environment:
  MYSQL57_URL            mysql://user:pass@host:port/database
  FINNHUB_API_KEY        optional, preferred provider
  POLYGON_API_KEY        optional fallback provider
  ALPHA_VANTAGE_API_KEY  optional fallback provider

Examples:
  python 05_Tools/reco_news_fetcher.py --provider finnhub --days 7 --limit 250
  python 05_Tools/reco_news_fetcher.py --provider auto --days 7 --limit 1000
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import os
import time
from typing import Any, Dict, Iterable, List, Optional
from urllib.parse import urlparse

import pymysql
import requests


def mysql_connection():
    url = os.environ.get("MYSQL57_URL")
    if not url:
        raise RuntimeError("MYSQL57_URL is not configured")
    parsed = urlparse(url)
    return pymysql.connect(
        host=parsed.hostname,
        port=parsed.port or 3306,
        user=parsed.username,
        password=parsed.password,
        database=parsed.path.lstrip("/"),
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True,
        charset="utf8mb4",
    )


def get_universe(conn, limit: int) -> List[str]:
    sql = """
        SELECT Scrip AS scrip
        FROM jstockdata_scrips
        WHERE UPPER(TRIM(COALESCE(RecoUniverseStatus, 'OMIT'))) = 'KEEP'
          AND COALESCE(RecoUniverseRank, 999999) <= 1000
          AND UPPER(TRIM(AssetClass)) IN ('EQ', 'ETF')
        ORDER BY RecoUniverseRank, Scrip
        LIMIT %s
    """
    with conn.cursor() as cur:
        cur.execute(sql, (limit,))
        return [row["scrip"] for row in cur.fetchall()]


def parse_date(value: Any) -> Optional[dt.datetime]:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return dt.datetime.utcfromtimestamp(value)
    if isinstance(value, str):
        text = value.replace("Z", "+00:00")
        try:
            parsed = dt.datetime.fromisoformat(text)
            if parsed.tzinfo:
                parsed = parsed.astimezone(dt.timezone.utc).replace(tzinfo=None)
            return parsed
        except ValueError:
            return None
    return None


def stable_url(provider: str, scrip: str, headline: str, published_at: Optional[dt.datetime], url: Optional[str]) -> str:
    if url:
        return url
    raw = f"{provider}|{scrip}|{headline}|{published_at or ''}"
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()
    return f"generated://{provider}/{scrip}/{digest}"


def fetch_finnhub(scrip: str, start: dt.date, end: dt.date, token: str) -> List[Dict[str, Any]]:
    url = "https://finnhub.io/api/v1/company-news"
    params = {"symbol": scrip, "from": start.isoformat(), "to": end.isoformat(), "token": token}
    data = requests.get(url, params=params, timeout=20).json()
    if not isinstance(data, list):
        return []
    rows = []
    for item in data:
        published_at = parse_date(item.get("datetime"))
        headline = (item.get("headline") or "").strip()
        if not headline:
            continue
        rows.append(
            {
                "provider": "finnhub",
                "scrip": scrip,
                "published_at": published_at,
                "source_name": item.get("source"),
                "headline": headline,
                "summary": item.get("summary"),
                "url": stable_url("finnhub", scrip, headline, published_at, item.get("url")),
                "provider_sentiment": None,
                "provider_score": None,
            }
        )
    return rows


def fetch_polygon(scrip: str, start: dt.date, _end: dt.date, token: str) -> List[Dict[str, Any]]:
    url = "https://api.polygon.io/v2/reference/news"
    params = {
        "ticker": scrip,
        "published_utc.gte": start.isoformat(),
        "order": "desc",
        "limit": 20,
        "apiKey": token,
    }
    data = requests.get(url, params=params, timeout=20).json()
    items = data.get("results", []) if isinstance(data, dict) else []
    rows = []
    for item in items:
        published_at = parse_date(item.get("published_utc"))
        headline = (item.get("title") or "").strip()
        if not headline:
            continue
        rows.append(
            {
                "provider": "polygon",
                "scrip": scrip,
                "published_at": published_at,
                "source_name": (item.get("publisher") or {}).get("name"),
                "headline": headline,
                "summary": item.get("description"),
                "url": stable_url("polygon", scrip, headline, published_at, item.get("article_url")),
                "provider_sentiment": None,
                "provider_score": None,
            }
        )
    return rows


def fetch_alpha_vantage(scrip: str, start: dt.date, _end: dt.date, token: str) -> List[Dict[str, Any]]:
    url = "https://www.alphavantage.co/query"
    time_from = start.strftime("%Y%m%dT0000")
    params = {
        "function": "NEWS_SENTIMENT",
        "tickers": scrip,
        "time_from": time_from,
        "limit": 50,
        "apikey": token,
    }
    data = requests.get(url, params=params, timeout=20).json()
    items = data.get("feed", []) if isinstance(data, dict) else []
    rows = []
    for item in items:
        published_at = parse_date(item.get("time_published"))
        headline = (item.get("title") or "").strip()
        if not headline:
            continue
        sentiment = item.get("overall_sentiment_label")
        score = item.get("overall_sentiment_score")
        rows.append(
            {
                "provider": "alpha_vantage",
                "scrip": scrip,
                "published_at": published_at,
                "source_name": item.get("source"),
                "headline": headline,
                "summary": item.get("summary"),
                "url": stable_url("alpha_vantage", scrip, headline, published_at, item.get("url")),
                "provider_sentiment": sentiment,
                "provider_score": score,
            }
        )
    return rows


def choose_provider(provider: str) -> str:
    if provider != "auto":
        return provider
    if os.environ.get("FINNHUB_API_KEY"):
        return "finnhub"
    if os.environ.get("POLYGON_API_KEY"):
        return "polygon"
    if os.environ.get("ALPHA_VANTAGE_API_KEY"):
        return "alpha_vantage"
    raise RuntimeError("No news API key found. Set FINNHUB_API_KEY, POLYGON_API_KEY, or ALPHA_VANTAGE_API_KEY.")


def fetch_news(provider: str, scrip: str, start: dt.date, end: dt.date) -> List[Dict[str, Any]]:
    if provider == "finnhub":
        token = os.environ.get("FINNHUB_API_KEY")
        if not token:
            raise RuntimeError("FINNHUB_API_KEY is not configured")
        return fetch_finnhub(scrip, start, end, token)
    if provider == "polygon":
        token = os.environ.get("POLYGON_API_KEY")
        if not token:
            raise RuntimeError("POLYGON_API_KEY is not configured")
        return fetch_polygon(scrip, start, end, token)
    if provider == "alpha_vantage":
        token = os.environ.get("ALPHA_VANTAGE_API_KEY")
        if not token:
            raise RuntimeError("ALPHA_VANTAGE_API_KEY is not configured")
        return fetch_alpha_vantage(scrip, start, end, token)
    raise ValueError(f"Unknown provider: {provider}")


def insert_rows(conn, rows: Iterable[Dict[str, Any]]) -> int:
    sql = """
        INSERT INTO jstockdata_reco_news_raw (
            provider, scrip, published_at, source_name, headline, summary, url,
            provider_sentiment, provider_score, fetched_at
        )
        VALUES (
            %(provider)s, %(scrip)s, %(published_at)s, %(source_name)s, %(headline)s,
            %(summary)s, %(url)s, %(provider_sentiment)s, %(provider_score)s, NOW()
        )
        ON DUPLICATE KEY UPDATE
            published_at = VALUES(published_at),
            source_name = VALUES(source_name),
            headline = VALUES(headline),
            summary = VALUES(summary),
            provider_sentiment = VALUES(provider_sentiment),
            provider_score = VALUES(provider_score),
            fetched_at = NOW()
    """
    count = 0
    with conn.cursor() as cur:
        for row in rows:
            cur.execute(sql, row)
            count += 1
    return count


def run_signal_refresh(conn, days: int) -> None:
    with conn.cursor() as cur:
        cur.execute("CALL reco_news_signal_refresh(%s)", (days,))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", choices=["auto", "finnhub", "polygon", "alpha_vantage"], default="auto")
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--limit", type=int, default=1000)
    parser.add_argument("--sleep", type=float, default=0.25, help="Delay between ticker requests")
    args = parser.parse_args()

    provider = choose_provider(args.provider)
    end = dt.datetime.utcnow().date()
    start = end - dt.timedelta(days=args.days)

    conn = mysql_connection()
    try:
        scrips = get_universe(conn, args.limit)
        total_rows = 0
        for idx, scrip in enumerate(scrips, start=1):
            try:
                rows = fetch_news(provider, scrip, start, end)
                inserted = insert_rows(conn, rows)
                total_rows += inserted
                print(f"{idx}/{len(scrips)} {scrip}: {inserted} rows")
            except Exception as exc:
                print(f"{idx}/{len(scrips)} {scrip}: ERROR {exc}")
            if args.sleep > 0:
                time.sleep(args.sleep)
        run_signal_refresh(conn, args.days)
        print(f"provider={provider} scrips={len(scrips)} raw_rows_seen={total_rows}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
