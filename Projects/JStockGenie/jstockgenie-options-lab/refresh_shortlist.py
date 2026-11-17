import json
import os
import sys
from urllib.parse import unquote, urlparse

import pymysql


SQL = """
SELECT s.SCRIP, s.AssetClass, 'BULLISH' AS direction, e.close
FROM jstockview_ema_score_board e
JOIN jstockview_smadelta_screener scr
  ON scr.scrip = e.scrip AND scr.FREQUENCY = 'DAILY'
JOIN jstockdata_scrips s
  ON s.scrip = e.scrip
WHERE e.DAILY_TOTAL_SCORE = 3
  AND e.WEEKLY_TOTAL_SCORE = 3
  AND scr.SMADeltaTrend <> 'EXIT'
UNION ALL
SELECT s.SCRIP, s.AssetClass, 'BEARISH' AS direction, e.close
FROM jstockview_ema_score_board e
JOIN jstockview_smadelta_screener scr
  ON scr.scrip = e.scrip AND scr.FREQUENCY = 'DAILY'
JOIN jstockdata_scrips s
  ON s.scrip = e.scrip
WHERE e.DAILY_TOTAL_SCORE = -3
  AND e.WEEKLY_TOTAL_SCORE = -3
  AND scr.SMADeltaTrend <> 'EXIT'
ORDER BY direction, SCRIP
"""


def main():
    raw_url = os.environ.get("MYSQL80_URL")
    if not raw_url:
        raise RuntimeError("MYSQL80_URL is not configured")
    parsed = urlparse(raw_url)
    connection = pymysql.connect(
        host=parsed.hostname,
        port=parsed.port or 3306,
        user=unquote(parsed.username or ""),
        password=unquote(parsed.password or ""),
        database=parsed.path.strip("/"),
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        connect_timeout=15,
        read_timeout=45,
    )
    try:
        with connection.cursor() as cursor:
            cursor.execute(SQL)
            rows = cursor.fetchall()
    finally:
        connection.close()

    shortlist = []
    seen = set()
    for row in rows:
        symbol = str(row["SCRIP"]).strip().upper()
        if not symbol or symbol in seen:
            continue
        seen.add(symbol)
        close = row.get("close")
        shortlist.append({
            "symbol": symbol,
            "direction": str(row["direction"]).strip().upper(),
            "assetClass": str(row["AssetClass"]).strip().upper(),
            "close": float(close) if close is not None else None,
        })
    if not shortlist:
        raise RuntimeError("The SQL screeners returned no shortlisted scrips")
    print(json.dumps({"shortlist": shortlist, "rowCount": len(shortlist)}))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
