"""Build a detailed long-only Aroon swing basket from the dated backtest CSV.

The report uses DAILY Aroon backtest rows for short swing holds and joins
current metadata/signal state from the MySQL 8 jstocksnp schema. Every daily
backtest symbol is retained so the CSV can be sorted and reviewed by its
actual return, win rate, drawdown, signal, AssetClass, and Rank. It writes
review-only CSV and Markdown output; it never places orders.
"""

from __future__ import annotations

import csv
import os
import urllib.parse
from datetime import datetime
from pathlib import Path

import pymysql


ROOT = Path(__file__).resolve().parents[2]
BACKTEST_CSV = ROOT / "AroonBacktest_20261010.csv"
REPORT_DIR = ROOT / "JStockGenie - 02.Robinhood Automation" / "03_Reports" / "Aroon"


def db_connection():
    raw_url = os.environ.get("MYSQL80_URL")
    if not raw_url:
        raise RuntimeError("MYSQL80_URL is not configured")
    parsed = urllib.parse.urlparse(raw_url)
    return pymysql.connect(
        host=parsed.hostname,
        port=parsed.port or 3306,
        user=parsed.username,
        password=parsed.password,
        database=parsed.path.lstrip("/"),
        cursorclass=pymysql.cursors.DictCursor,
        connect_timeout=15,
    )


def as_float(row: dict, key: str) -> float:
    return float(row[key])


def load_backtest_rows() -> list[dict]:
    with BACKTEST_CSV.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))

    selected = []
    for row in rows:
        if row["schema"] != "jstocksnp" or row["frequency"] != "DAILY":
            continue
        selected.append(row)
    return selected


def load_current_context(symbols: list[str]) -> dict[str, dict]:
    if not symbols:
        return {}

    placeholders = ",".join(["%s"] * len(symbols))
    connection = db_connection()
    try:
        with connection.cursor() as cursor:
            cursor.execute(
                f"""
                    SELECT
                    s.`Scrip` AS scrip,
                    UPPER(TRIM(COALESCE(s.`AssetClass`, 'UNKNOWN'))) AS assetclass,
                    s.`Rank` AS source_rank,
                    s.`RecoUniverseStatus` AS reco_universe_status,
                    s.`RecoUniverseRank` AS reco_universe_rank
                FROM `jstockdata_scrips` s
                WHERE s.`Scrip` IN ({placeholders})
                """,
                symbols,
            )
            metadata = {row["scrip"]: row for row in cursor.fetchall()}

            cursor.execute(
                f"""
                SELECT
                    e.`SCRIP` AS scrip,
                    TRIM(REPLACE(e.`FREQUENCY`, CHAR(13), '')) AS frequency,
                    e.`DATE` AS signal_date,
                    e.`Aroon_Up` AS aroon_up,
                    e.`Aroon_Down` AS aroon_down,
                    UPPER(TRIM(REPLACE(COALESCE(e.`Aroon_Signal`, ''), CHAR(13), ''))) AS aroon_signal,
                    h.`CLOSE` AS close_price
                FROM `jstockdata_hatrend_extend` e
                LEFT JOIN `jstockdata_hatrend` h
                  ON h.`SCRIP` = e.`SCRIP`
                 AND TRIM(REPLACE(h.`FREQUENCY`, CHAR(13), '')) = TRIM(REPLACE(e.`FREQUENCY`, CHAR(13), ''))
                 AND h.`DATE` = e.`DATE`
                JOIN (
                    SELECT `SCRIP`, MAX(`DATE`) AS max_date
                    FROM `jstockdata_hatrend_extend`
                    WHERE TRIM(REPLACE(`FREQUENCY`, CHAR(13), '')) = 'DAILY'
                      AND `SCRIP` IN ({placeholders})
                    GROUP BY `SCRIP`
                ) latest
                  ON latest.`SCRIP` = e.`SCRIP`
                 AND latest.max_date = e.`DATE`
                WHERE TRIM(REPLACE(e.`FREQUENCY`, CHAR(13), '')) = 'DAILY'
                  AND e.`SCRIP` IN ({placeholders})
                """,
                symbols + symbols,
            )
            current = {row["scrip"]: row for row in cursor.fetchall()}
    finally:
        connection.close()

    result = {}
    for symbol in symbols:
        result[symbol] = {**metadata.get(symbol, {}), **current.get(symbol, {})}
    return result


def score(row: dict) -> float:
    """Transparent quality score; higher is better, not a return forecast."""
    win_rate = min(max(as_float(row, "win_rate_pct"), 0), 100)
    cagr = min(max(as_float(row, "cagr_pct"), 0), 100)
    drawdown = min(abs(as_float(row, "max_drawdown_pct")), 35)
    trades = min(int(row["trades"]), 10)
    sample_factor = trades / 10.0
    return round((0.50 * win_rate + 0.30 * cagr - 0.20 * drawdown) * sample_factor, 4)


def build_rows() -> list[dict]:
    backtest = load_backtest_rows()
    symbols = [row["scrip"] for row in backtest]
    context = load_current_context(symbols)
    output = []
    for row in backtest:
        metadata = context.get(row["scrip"], {})
        current_signal = metadata.get("aroon_signal", "")
        output.append(
            {
                "symbol": row["scrip"],
                "assetclass": metadata.get("assetclass", "UNKNOWN"),
                "rank": metadata.get("source_rank"),
                "reco_universe_rank": metadata.get("reco_universe_rank"),
                "frequency": "DAILY",
                "trade": "BUY / HOLD / SELL",
                "aroon_signal": current_signal,
                "signal_date": metadata.get("signal_date"),
                "close_price": metadata.get("close_price"),
                "aroon_up": metadata.get("aroon_up"),
                "aroon_down": metadata.get("aroon_down"),
                "strategy_return_pct": row["strategy_return_pct"],
                "cagr_pct": row["cagr_pct"],
                "win_rate_pct": row["win_rate_pct"],
                "trades": row["trades"],
                "max_drawdown_pct": row["max_drawdown_pct"],
                "buy_hold_return_pct": row["buy_hold_return_pct"],
                "outperformance_pct": row["outperformance_pct"],
                "basket_score": score(row),
                "start_date": row["start_date"],
                "end_date": row["end_date"],
            }
        )

    output.sort(
        key=lambda item: (
            -float(item["basket_score"]),
            -float(item["win_rate_pct"]),
            -float(item["cagr_pct"]),
            float(item["max_drawdown_pct"]),
            item["symbol"],
        )
    )
    for index, item in enumerate(output, start=1):
        item["basket_rank"] = index
    return output


def write_reports(rows: list[dict]) -> tuple[Path, Path]:
    stamp = datetime.now().strftime("%Y%m%d")
    output_dir = REPORT_DIR / stamp
    output_dir.mkdir(parents=True, exist_ok=True)
    csv_path = output_dir / f"Aroon_Swing_Basket_{stamp}.csv"
    md_path = output_dir / f"Aroon_Swing_Basket_{stamp}.md"

    columns = [
        "basket_rank", "symbol", "assetclass", "rank", "reco_universe_rank",
        "frequency", "trade", "aroon_signal", "signal_date", "close_price",
        "aroon_up", "aroon_down", "strategy_return_pct", "cagr_pct",
        "win_rate_pct", "trades", "max_drawdown_pct", "buy_hold_return_pct",
        "outperformance_pct", "basket_score", "start_date", "end_date",
    ]
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)

    with md_path.open("w", encoding="utf-8") as handle:
        handle.write("# Aroon Daily Swing Basket\n\n")
        handle.write(f"Generated: {datetime.now():%Y-%m-%d %H:%M} America/Chicago\n\n")
        handle.write("This is a review-only basket. It contains every DAILY long-only Aroon backtest row and the latest daily Aroon state. A BUY state means buy/hold until the Aroon SELL transition; it is not an automatic order instruction.\n\n")
        handle.write("No win-rate, return, drawdown, current-signal, or universe-status rows were removed. Use the metrics and ranks to select candidates for further review.\n\n")
        if rows:
            handle.write("| Rank | Symbol | AssetClass | Source Rank | Close | Return % | CAGR % | Win % | Trades | Max DD % | Score |\n")
            handle.write("|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|\n")
            for item in rows:
                handle.write(
                    f"| {item['basket_rank']} | {item['symbol']} | {item['assetclass']} | {item['rank'] or ''} | "
                    f"{item['close_price'] or ''} | {item['strategy_return_pct']} | {item['cagr_pct']} | "
                    f"{item['win_rate_pct']} | {item['trades']} | {item['max_drawdown_pct']} | {item['basket_score']} |\n"
                )
        else:
            handle.write("No current weekly Aroon BUY candidates met the selection filters.\n")
    return csv_path, md_path


if __name__ == "__main__":
    csv_path, md_path = write_reports(build_rows())
    print(csv_path)
    print(md_path)
