#!/usr/bin/env python3
"""Fetch live leveraged-ETF quotes and create review-only dip alerts.

The monitor never places an order. It combines live Yahoo chart quotes with the
latest EOD Java Trend row stored in MySQL 8. A falling price only becomes an
ADD_REVIEW alert while the EOD trend remains aligned.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from decimal import Decimal
from typing import Any
from urllib.parse import unquote, urlparse

import pymysql


PROVIDER = "YAHOO_CHART"


def mysql_connection() -> pymysql.connections.Connection:
    url = os.environ.get("MYSQL80_URL")
    if not url:
        raise RuntimeError("MYSQL80_URL is not configured")
    parsed = urlparse(url)
    return pymysql.connect(
        host=parsed.hostname,
        port=parsed.port or 3306,
        user=unquote(parsed.username or ""),
        password=unquote(parsed.password or ""),
        database=parsed.path.lstrip("/"),
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
        connect_timeout=15,
        read_timeout=60,
        write_timeout=60,
    )


def fetch_quote(scrip: str) -> dict[str, Any]:
    encoded = urllib.parse.quote(scrip)
    url = (
        f"https://query1.finance.yahoo.com/v8/finance/chart/{encoded}"
        "?interval=1m&range=1d&includePrePost=false"
    )
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.load(response)
    result = payload["chart"]["result"][0]
    meta = result["meta"]
    quote_time = meta.get("regularMarketTime")
    market_state = str(meta.get("marketState") or "").upper()
    if not market_state:
        now_epoch = int(time.time())
        periods = meta.get("currentTradingPeriod") or {}
        market_state = "CLOSED"
        for state_name in ("pre", "regular", "post"):
            period = periods.get(state_name) or {}
            if int(period.get("start") or 0) <= now_epoch < int(period.get("end") or 0):
                market_state = state_name.upper()
                break
    return {
        "scrip": scrip,
        "live_price": Decimal(str(meta["regularMarketPrice"])),
        "previous_close": Decimal(str(meta.get("previousClose")))
        if meta.get("previousClose") is not None
        else None,
        "market_state": market_state,
        "quote_at_utc": dt.datetime.fromtimestamp(quote_time, dt.timezone.utc).replace(tzinfo=None)
        if quote_time
        else None,
    }


def load_inputs(cursor: pymysql.cursors.DictCursor, basket: str) -> list[dict[str, Any]]:
    cursor.execute(
        """
        SELECT c.basket, c.scrip, c.enabled,
               c.dip_level_1_pct, c.dip_level_2_pct, c.dip_level_3_pct,
               c.add_level_1_capital_pct, c.add_level_2_capital_pct,
               c.add_level_3_capital_pct, c.max_alerts_per_month,
               c.cooldown_minutes, c.cash_reserve_pct,
               c.required_opti_direction, c.required_opti_last_signal,
               c.min_opti_strength_pct, c.max_opti_days_since,
               c.review_only
        FROM jstockdata_reco_leveraged_dip_config c
        WHERE c.basket = %s AND c.enabled = 1
        ORDER BY c.scrip
        """,
        (basket,),
    )
    configs = cursor.fetchall()
    if not configs:
        raise RuntimeError(f"No enabled monitor configuration found for basket {basket}")

    for config in configs:
        cursor.execute(
            """
            SELECT e.DATE AS eod_date, e.Close AS eod_close,
                   e.SMADeltaTrend AS sma_delta_trend,
                   e.LODeltaSignal AS lo_delta_signal,
                   e.Combined_Signal AS combined_signal,
                   e.Opti_LastSignal AS opti_last_signal,
                   e.Opti_ChancePct AS opti_chance_pct,
                   e.Opti_Direction AS opti_direction,
                   e.Opti_DirectionPct AS opti_direction_pct,
                   e.Opti_StrengthPct AS opti_strength_pct,
                   e.Opti_DaysSince AS opti_days_since,
                   e.Opti_PriceChangePct AS opti_price_change_pct
            FROM jstockdata_hatrend_extend e
            WHERE e.SCRIP = %s
              AND REPLACE(e.FREQUENCY, CHAR(13), '') = 'DAILY'
            ORDER BY e.DATE DESC
            LIMIT 1
            """,
            (config["scrip"],),
        )
        config.update(cursor.fetchone() or {})
    return configs


def trigger_for(config: dict[str, Any], drop_pct: Decimal) -> tuple[int, Decimal]:
    if drop_pct >= Decimal(str(config["dip_level_3_pct"])):
        return 3, Decimal(str(config["add_level_3_capital_pct"]))
    if drop_pct >= Decimal(str(config["dip_level_2_pct"])):
        return 2, Decimal(str(config["add_level_2_capital_pct"]))
    if drop_pct >= Decimal(str(config["dip_level_1_pct"])):
        return 1, Decimal(str(config["add_level_1_capital_pct"]))
    return 0, Decimal("0")


def recent_alert_state(
    cursor: pymysql.cursors.DictCursor, basket: str, scrip: str
) -> tuple[int, dt.datetime | None]:
    cursor.execute(
        """
        SELECT COUNT(*) AS month_alerts, MAX(observed_at) AS last_alert_at
        FROM jstockdata_reco_leveraged_dip_monitor_log
        WHERE basket = %s AND scrip = %s
          AND action_status = 'ADD_REVIEW'
          AND observed_at >= DATE_FORMAT(CURRENT_DATE, '%%Y-%%m-01')
        """,
        (basket, scrip),
    )
    row = cursor.fetchone()
    return int(row["month_alerts"] or 0), row["last_alert_at"]


def evaluate(
    cursor: pymysql.cursors.DictCursor,
    config: dict[str, Any],
    quote: dict[str, Any],
    now_utc: dt.datetime,
) -> dict[str, Any]:
    eod_close = config.get("eod_close")
    if not eod_close:
        return {"trigger_level": 0, "add_pct": Decimal("0"), "status": "MISSING_EOD", "reason": "No latest EOD Java Trend row."}

    change_pct = (quote["live_price"] / Decimal(str(eod_close)) - Decimal("1")) * Decimal("100")
    drop_pct = -change_pct
    trigger_level, add_pct = trigger_for(config, drop_pct)
    quote_at = quote.get("quote_at_utc")
    stale_minutes = (now_utc - quote_at).total_seconds() / 60 if quote_at else 10**9

    if quote["market_state"] != "REGULAR":
        status, reason = "MARKET_CLOSED", "Quote logged; add reviews run only during the regular session."
    elif stale_minutes > 20:
        status, reason = "QUOTE_STALE", f"Quote is {stale_minutes:.0f} minutes old."
    elif trigger_level == 0:
        status, reason = "NO_DIP", "Live decline has not reached the first configured level."
    elif not (
        str(config.get("combined_signal") or "").upper() == "BUY"
        and str(config.get("sma_delta_trend") or "").upper() == "UP"
        and str(config.get("lo_delta_signal") or "").upper() != "SELL"
    ):
        status, reason = "BLOCKED_SIGNAL", "Dip reached, but the latest EOD Java Trend is not fully aligned for an add."
    elif not (
        str(config.get("opti_direction") or "").upper()
        == str(config["required_opti_direction"]).upper()
        and str(config.get("opti_last_signal") or "").upper()
        == str(config["required_opti_last_signal"]).upper()
        and Decimal(str(config.get("opti_strength_pct") or 0))
        >= Decimal(str(config["min_opti_strength_pct"]))
        and int(config.get("opti_days_since") or 10**6) <= int(config["max_opti_days_since"])
    ):
        status, reason = "BLOCKED_OPTITREND", "Dip reached, but OptiTrend direction, signal, strength, or freshness is not aligned for an add."
    else:
        month_alerts, last_alert_at = recent_alert_state(cursor, config["basket"], config["scrip"])
        cooldown = dt.timedelta(minutes=int(config["cooldown_minutes"]))
        if month_alerts >= int(config["max_alerts_per_month"]):
            status, reason = "MONTHLY_CAP", "Monthly review-alert cap reached; no additional averaging-down alert."
        elif last_alert_at and dt.datetime.utcnow() - last_alert_at < cooldown:
            status, reason = "COOLDOWN", "A recent add review is still inside the configured cooldown."
        else:
            status = "ADD_REVIEW"
            reason = (
                f"Level {trigger_level} dip with aligned EOD trend. Review an add capped at "
                f"{add_pct}% of account capital while preserving {config['cash_reserve_pct']}% cash."
            )

    return {
        "change_pct": change_pct.quantize(Decimal("0.0001")),
        "trigger_level": trigger_level,
        "add_pct": add_pct,
        "status": status,
        "reason": reason,
    }


def insert_quote(cursor: pymysql.cursors.DictCursor, quote: dict[str, Any]) -> None:
    cursor.execute(
        """
        INSERT INTO jstockdata_live_quote_snapshot
            (quote_at_utc, provider, market_state, scrip, live_price, provider_previous_close)
        VALUES (%s, %s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
            observed_at = CURRENT_TIMESTAMP,
            market_state = VALUES(market_state),
            live_price = VALUES(live_price),
            provider_previous_close = VALUES(provider_previous_close)
        """,
        (
            quote["quote_at_utc"], PROVIDER, quote["market_state"], quote["scrip"],
            quote["live_price"], quote["previous_close"],
        ),
    )


def insert_monitor_log(
    cursor: pymysql.cursors.DictCursor,
    config: dict[str, Any],
    quote: dict[str, Any],
    result: dict[str, Any],
) -> None:
    cursor.execute(
        """
        INSERT INTO jstockdata_reco_leveraged_dip_monitor_log
            (basket, scrip, quote_at_utc, market_state, eod_date, eod_close,
             live_price, change_from_eod_pct, sma_delta_trend, lo_delta_signal,
             combined_signal, opti_last_signal, opti_chance_pct, opti_direction,
             opti_direction_pct, opti_strength_pct, opti_days_since,
             opti_price_change_pct, trigger_level, suggested_add_capital_pct,
             action_status, reason)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            config["basket"], config["scrip"], quote["quote_at_utc"], quote["market_state"],
            config.get("eod_date"), config.get("eod_close"), quote["live_price"],
            result.get("change_pct"), config.get("sma_delta_trend"),
            config.get("lo_delta_signal"), config.get("combined_signal"),
            config.get("opti_last_signal"), config.get("opti_chance_pct"),
            config.get("opti_direction"), config.get("opti_direction_pct"),
            config.get("opti_strength_pct"), config.get("opti_days_since"),
            config.get("opti_price_change_pct"),
            result["trigger_level"], result["add_pct"], result["status"], result["reason"],
        ),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--basket", default="SNP-ETF-LEVG")
    parser.add_argument("--no-write", action="store_true", help="Evaluate without writing quote or monitor rows")
    args = parser.parse_args()

    connection = mysql_connection()
    try:
        with connection.cursor() as cursor:
            configs = load_inputs(cursor, args.basket)
            symbols = [row["scrip"] for row in configs]
            with concurrent.futures.ThreadPoolExecutor(max_workers=min(5, len(symbols))) as pool:
                futures = {pool.submit(fetch_quote, symbol): symbol for symbol in symbols}
                quotes = {}
                errors = {}
                for future in concurrent.futures.as_completed(futures):
                    symbol = futures[future]
                    try:
                        quotes[symbol] = future.result()
                    except Exception as exc:  # Keep the remaining basket observable.
                        errors[symbol] = str(exc)

            now_utc = dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)
            results = []
            for config in configs:
                symbol = config["scrip"]
                quote = quotes.get(symbol)
                if quote is None:
                    results.append({"scrip": symbol, "status": "QUOTE_ERROR", "reason": errors.get(symbol, "Unknown quote error")})
                    continue
                result = evaluate(cursor, config, quote, now_utc)
                row = {
                    "scrip": symbol,
                    "live_price": float(quote["live_price"]),
                    "eod_close": float(config["eod_close"]) if config.get("eod_close") else None,
                    "change_from_eod_pct": float(result.get("change_pct", 0)),
                    "combined_signal": config.get("combined_signal"),
                    "opti_last_signal": config.get("opti_last_signal"),
                    "opti_chance_pct": float(config["opti_chance_pct"]) if config.get("opti_chance_pct") is not None else None,
                    "opti_direction": config.get("opti_direction"),
                    "opti_strength_pct": float(config["opti_strength_pct"]) if config.get("opti_strength_pct") is not None else None,
                    "opti_days_since": config.get("opti_days_since"),
                    "trigger_level": result["trigger_level"],
                    "suggested_add_capital_pct": float(result["add_pct"]),
                    "status": result["status"],
                    "reason": result["reason"],
                }
                results.append(row)
                if not args.no_write:
                    insert_quote(cursor, quote)
                    insert_monitor_log(cursor, config, quote, result)

            if args.no_write:
                connection.rollback()
            else:
                connection.commit()
            print(json.dumps({"basket": args.basket, "provider": PROVIDER, "results": results}, indent=2))
            return 0 if not errors else 2
    finally:
        connection.close()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(json.dumps({"status": "ERROR", "error": str(exc)}), file=sys.stderr)
        raise SystemExit(1)
