import csv
import re
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path

import pymysql


ROOT = Path(r"D:\Codex\Projects\JStockGenie")
PROJECT = ROOT / "JStockGenie - 03.Fidelity and Market Analysis"
ENV_PATH = ROOT / "JStockGenie - 01.Trend and Recos" / "MySQL57.env"
STOCKANALYSIS_CSV = (
    PROJECT
    / "outputs"
    / "stockanalysis_screeners_20260801"
    / "StockAnalysis_JSG_All_Enriched_Screener_Rows_20260801.csv"
)


def load_env(path):
    env = {}
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            env[key.strip()] = value.strip()
    return env


def mysql_conn():
    env = load_env(ENV_PATH)
    return pymysql.connect(
        host=env["MYSQL57_HOST"],
        port=int(env["MYSQL57_PORT"]),
        user=env["MYSQL57_DBUSER"],
        password=env["MYSQL57_DBPASS"],
        database=env["MYSQL57_DBNAME"],
        autocommit=False,
        cursorclass=pymysql.cursors.DictCursor,
    )


def parse_yyyymmdd(value):
    if value in (None, ""):
        return None
    return datetime.strptime(str(value), "%Y%m%d").date()


def clean_pct(value):
    if value is None:
        return None
    text = str(value).strip()
    if not text or text == "-":
        return None
    text = text.replace("%", "").replace(",", "")
    try:
        return Decimal(text)
    except InvalidOperation:
        return None


def clean_decimal(value):
    if value is None:
        return None
    text = str(value).strip()
    if not text or text == "-":
        return None
    text = text.replace("$", "").replace(",", "").replace("%", "")
    try:
        return Decimal(text)
    except InvalidOperation:
        return None


def premium_roi(value):
    if not value:
        return None
    match = re.search(r"([-+]?\d+(?:\.\d+)?)\s*%", str(value))
    return Decimal(match.group(1)) if match else None


def clip(value, low=0, high=100):
    return max(low, min(high, float(value)))


def signal_points(signal, weight):
    if not signal:
        return 0
    text = str(signal).upper()
    if "STRONG" in text and ("BUY" in text or "BULL" in text):
        return weight
    if "BUY" in text or "BULL" in text or "UP" in text:
        return weight * 0.75
    if "SELL" in text or "BEAR" in text or "DOWN" in text:
        return -weight * 0.75
    return 0


def momentum_points(direction, phase, confidence, weight):
    points = signal_points(direction, weight)
    conf = float(confidence or 65) / 100.0
    points *= max(0.35, min(conf, 1.0))
    phase_text = str(phase or "").upper()
    if "ACCELERATING" in phase_text:
        points += weight * 0.20
    if "REVERSAL" in phase_text or "EXHAUST" in phase_text:
        points -= weight * 0.25
    return points


def score_from_0_100(value, neutral=50, scale=0.5):
    if value is None:
        return neutral
    return clip(neutral + float(value) * scale)


def verdict_from_score(score):
    if score is None:
        return "WATCH"
    if score >= 80:
        return "STRONG BUY"
    if score >= 68:
        return "BUY"
    if score >= 55:
        return "WATCH"
    if score >= 42:
        return "HOLD"
    if score >= 30:
        return "TRIM / AVOID"
    return "AVOID"


def direction_from_score(score):
    if score >= 66:
        return "BULLISH"
    if score <= 40:
        return "BEARISH"
    return "NEUTRAL"


def suitability(score, high_text="High"):
    if score >= 75:
        return high_text
    if score >= 60:
        return "Medium"
    if score >= 45:
        return "Low"
    return "Avoid"


def load_stockanalysis_rows():
    rows = {}
    if not STOCKANALYSIS_CSV.exists():
        return rows
    with STOCKANALYSIS_CSV.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            scrip = (row.get("Symbol") or "").strip().upper()
            assetclass = (row.get("AssetClass") or "").strip().upper()
            if not scrip:
                continue
            rows[(scrip, assetclass)] = {
                "name": row.get("Name"),
                "close_price": clean_decimal(row.get("Close Price")),
                "dividend_yield": clean_pct(row.get("Dividend Yield")),
                "growth_score": clean_decimal(row.get("Growth Score")),
                "optionable": (row.get("Optionable") or "").strip().lower() == "yes",
                "weekly_verdict": row.get("Weekly Verdict"),
                "direction": row.get("Direction"),
                "confidence_pct": clean_decimal(row.get("Confidence %")),
                "sell_put_suitability": row.get("SELL PUT Suitability"),
                "sell_call_suitability": row.get("SELL CALL Suitability"),
                "premium_roi": premium_roi(row.get("Premium ROI")),
                "premium_roi_text": row.get("Premium ROI"),
                "notes": row.get("Notes"),
            }
    return rows


def fetch_map(cur, sql, key_fields):
    cur.execute(sql)
    result = {}
    for row in cur.fetchall():
        key = tuple(str(row[field]).upper() for field in key_fields)
        result[key] = row
    return result


def main():
    stockanalysis = load_stockanalysis_rows()
    conn = mysql_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT MAX(DATE) max_daily FROM jstockdata_hatrend_extend WHERE FREQUENCY='DAILY'")
            max_daily = cur.fetchone()["max_daily"]
            cur.execute("SELECT MAX(DATE) max_weekly FROM jstockdata_hatrend_extend WHERE FREQUENCY='WEEKLY'")
            max_weekly = cur.fetchone()["max_weekly"]
            cur.execute("SELECT MAX(generated_at) max_generated FROM jstockdata_reco_momentum_signal")
            momentum_generated = cur.fetchone()["max_generated"]

            analysis_date = date.today()
            trend_build_date = parse_yyyymmdd(max_daily)
            run_name = f"JSG Fusion Signal {analysis_date:%Y-%m-%d} after Java Trend {max_daily}"
            cur.execute(
                """
                INSERT INTO jstockdata_fusion_run
                    (run_name, trend_build_date, analysis_date, status, source_note)
                VALUES
                    (%s, %s, %s, 'RUNNING', %s)
                """,
                (
                    run_name,
                    trend_build_date,
                    analysis_date,
                    "Internal: Java Trend through daily %s / weekly %s. External: StockAnalysis CSV 20260801."
                    % (max_daily, max_weekly),
                ),
            )
            run_id = cur.lastrowid

            cur.execute(
                """
                SELECT
                    `Rank` AS universe_rank,
                    UPPER(Scrip) AS scrip,
                    `Company Name` AS company_name,
                    UPPER(AssetClass) AS assetclass,
                    RecoUniverseStatus AS reco_universe_status,
                    RecoUniverseRank AS reco_universe_rank
                FROM jstockdata_scrips
                WHERE Scrip IS NOT NULL AND Scrip <> ''
                """
            )
            universe = cur.fetchall()

            cur.execute(
                """
                SELECT DISTINCT UPPER(scrip) AS scrip
                FROM jstockdata_current_positions
                WHERE scrip IS NOT NULL AND scrip <> ''
                """
            )
            positions = {row["scrip"] for row in cur.fetchall()}

            base_rows = []
            for row in universe:
                key = (row["scrip"], row["assetclass"])
                external = stockanalysis.get(key, {})
                base_rows.append(
                    (
                        run_id,
                        row["scrip"],
                        row["assetclass"],
                        row["company_name"],
                        row["universe_rank"],
                        row["reco_universe_status"],
                        row["reco_universe_rank"],
                        1 if row["scrip"] in positions else 0,
                        None if "optionable" not in external else int(external["optionable"]),
                        "jstockdata_scrips",
                    )
                )
            cur.executemany(
                """
                INSERT INTO jstockdata_fusion_base_universe
                    (run_id, scrip, assetclass, company_name, universe_rank, reco_universe_status,
                     reco_universe_rank, is_current_position, is_optionable, source_table)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                base_rows,
            )

            daily_hte = fetch_map(
                cur,
                """
                SELECT UPPER(SCRIP) scrip, Combined_Signal, Combined_Signal_Ind,
                       LODeltaSignal, SMADeltaTrend, DATE
                FROM jstockdata_hatrend_extend
                WHERE FREQUENCY='DAILY' AND DATE = (SELECT MAX(DATE) FROM jstockdata_hatrend_extend WHERE FREQUENCY='DAILY')
                """,
                ["scrip"],
            )
            weekly_hte = fetch_map(
                cur,
                """
                SELECT UPPER(SCRIP) scrip, Combined_Signal, Combined_Signal_Ind,
                       LODeltaSignal, SMADeltaTrend, DATE
                FROM jstockdata_hatrend_extend
                WHERE FREQUENCY='WEEKLY' AND DATE = (SELECT MAX(DATE) FROM jstockdata_hatrend_extend WHERE FREQUENCY='WEEKLY')
                """,
                ["scrip"],
            )
            daily_mom = fetch_map(
                cur,
                """
                SELECT *
                FROM jstockdata_reco_momentum_signal
                WHERE frequency='DAILY'
                  AND generated_at = (SELECT MAX(generated_at) FROM jstockdata_reco_momentum_signal)
                """,
                ["scrip"],
            )
            weekly_mom = fetch_map(
                cur,
                """
                SELECT *
                FROM jstockdata_reco_momentum_signal
                WHERE frequency='WEEKLY'
                  AND generated_at = (SELECT MAX(generated_at) FROM jstockdata_reco_momentum_signal)
                """,
                ["scrip"],
            )
            quant = fetch_map(
                cur,
                """
                SELECT *
                FROM jstockdata_reco_quant_score
                WHERE generated_at = (SELECT MAX(generated_at) FROM jstockdata_reco_quant_score)
                """,
                ["scrip"],
            )

            cur.execute(
                """
                SELECT o.*
                FROM jstockdata_reco_options o
                JOIN (
                    SELECT scrip, option_type, MAX(recommendation_score) max_score
                    FROM jstockdata_reco_options
                    WHERE generated_at = (SELECT MAX(generated_at) FROM jstockdata_reco_options)
                    GROUP BY scrip, option_type
                ) best
                  ON best.scrip = o.scrip
                 AND best.option_type = o.option_type
                 AND best.max_score = o.recommendation_score
                WHERE o.generated_at = (SELECT MAX(generated_at) FROM jstockdata_reco_options)
                """
            )
            options_by_scrip = {}
            for row in cur.fetchall():
                key = str(row["scrip"]).upper()
                option_type = str(row["option_type"]).upper()
                options_by_scrip.setdefault(key, {})[option_type] = row

            internal_rows = []
            external_rows = []
            score_rows = []
            verdict_rows = []
            history_rows = []
            score_lookup = {}
            verdict_lookup = {}

            for row in universe:
                scrip = row["scrip"]
                assetclass = row["assetclass"]
                key = (scrip, assetclass)
                d_hte = daily_hte.get((scrip,), {})
                w_hte = weekly_hte.get((scrip,), {})
                d_mom = daily_mom.get((scrip,), {})
                w_mom = weekly_mom.get((scrip,), {})
                q = quant.get((scrip,), {})
                ext = stockanalysis.get(key, {})
                opts = options_by_scrip.get(scrip, {})
                put = opts.get("PUT", {})
                call = opts.get("CALL", {})

                daily_signal = d_hte.get("Combined_Signal") or d_mom.get("combined_signal")
                weekly_signal = w_hte.get("Combined_Signal") or w_mom.get("combined_signal")
                daily_conf = d_mom.get("momentum_confidence_pct")
                weekly_conf = w_mom.get("momentum_confidence_pct")
                weekly_verdict = ext.get("weekly_verdict")
                direction_score_base = 50

                short_score = direction_score_base
                short_score += signal_points(daily_signal, 18)
                short_score += momentum_points(
                    d_mom.get("momentum_direction"),
                    d_mom.get("momentum_phase"),
                    daily_conf,
                    18,
                )
                short_score += signal_points(weekly_signal, 8)
                short_score += score_from_0_100(d_mom.get("predicted_5bar_return_pct"), 50, 2) - 50
                short_score -= float(d_mom.get("momentum_reversal_risk_pct") or 0) * 0.08

                mid_score = 50
                mid_score += signal_points(weekly_signal, 20)
                mid_score += momentum_points(
                    w_mom.get("momentum_direction"),
                    w_mom.get("momentum_phase"),
                    weekly_conf,
                    18,
                )
                mid_score += signal_points(daily_signal, 8)
                mid_score += score_from_0_100(w_mom.get("predicted_5bar_return_pct"), 50, 1.5) - 50
                mid_score += (float(q.get("trend_score") or 50) - 50) * 0.12
                mid_score -= float(w_mom.get("momentum_reversal_risk_pct") or 0) * 0.06

                growth = ext.get("growth_score")
                dividend = ext.get("dividend_yield")
                long_score = 50
                long_score += signal_points(weekly_signal, 16)
                long_score += momentum_points(
                    w_mom.get("momentum_direction"),
                    w_mom.get("momentum_phase"),
                    weekly_conf,
                    12,
                )
                long_score += (float(q.get("quality_score") or 50) - 50) * 0.16
                long_score += (float(q.get("quant_score") or 50) - 50) * 0.14
                if growth is not None:
                    long_score += (float(growth) - 50) * 0.18
                if dividend is not None:
                    long_score += min(float(dividend), 8) * 0.8

                risk_score = 25
                risk_score += float(d_mom.get("momentum_reversal_risk_pct") or 0) * 0.35
                risk_score += float(w_mom.get("momentum_reversal_risk_pct") or 0) * 0.25
                risk_score += 12 if signal_points(daily_signal, 1) < 0 else 0
                risk_score += 12 if signal_points(weekly_signal, 1) < 0 else 0
                risk_score -= 8 if ext.get("direction") == "BULLISH" else 0

                premium = ext.get("premium_roi")
                put_roi = put.get("premium_roi_pct") if put else premium
                call_roi = call.get("premium_roi_pct") if call else premium
                optionable = ext.get("optionable") or bool(put or call)

                sell_put_score = 25
                sell_put_score += 25 if optionable else -20
                sell_put_score += clip(short_score, 0, 100) * 0.25
                sell_put_score += clip(mid_score, 0, 100) * 0.15
                sell_put_score += min(float(put_roi or 0), 15) * 2.0
                sell_put_score -= clip(risk_score, 0, 100) * 0.15
                if str(ext.get("sell_put_suitability") or "").upper() == "HIGH":
                    sell_put_score += 8

                sell_call_score = 25
                sell_call_score += 20 if scrip in positions else 0
                sell_call_score += 20 if optionable else -20
                sell_call_score += (100 - clip(short_score, 0, 100)) * 0.12
                sell_call_score += min(float(call_roi or 0), 15) * 1.8
                if "COVERED" in str(ext.get("sell_call_suitability") or "").upper():
                    sell_call_score += 8

                investment_score = clip(long_score * 0.60 + mid_score * 0.25 + (100 - risk_score) * 0.15)
                fusion_score = clip(
                    short_score * 0.22
                    + mid_score * 0.28
                    + long_score * 0.30
                    + sell_put_score * 0.10
                    + investment_score * 0.10
                    - max(risk_score - 60, 0) * 0.15
                )
                confidence = clip(
                    40
                    + (float(daily_conf or 0) * 0.20)
                    + (float(weekly_conf or 0) * 0.25)
                    + (10 if q else 0)
                    + (10 if ext else 0)
                    + (5 if opts else 0)
                )
                direction = direction_from_score(fusion_score)

                internal_rows.append(
                    (
                        run_id,
                        scrip,
                        assetclass,
                        daily_signal,
                        weekly_signal,
                        d_mom.get("momentum_direction"),
                        daily_conf,
                        w_mom.get("momentum_direction"),
                        weekly_conf,
                        weekly_verdict,
                        direction,
                        confidence,
                        trend_build_date,
                        "Fresh daily/weekly trend and momentum loaded from Java Trend output.",
                    )
                )

                if ext:
                    external_rows.extend(
                        [
                            (run_id, scrip, assetclass, "StockAnalysis_20260801", "Fundamental", "Dividend Yield", ext.get("dividend_yield"), ext.get("dividend_yield"), None, None, "LONG", date(2026, 8, 1), None, ext.get("notes")),
                            (run_id, scrip, assetclass, "StockAnalysis_20260801", "Fundamental", "Growth Score", ext.get("growth_score"), ext.get("growth_score"), ext.get("growth_score"), ext.get("confidence_pct"), "LONG", date(2026, 8, 1), None, ext.get("notes")),
                            (run_id, scrip, assetclass, "StockAnalysis_20260801", "Options", "Optionable", "Yes" if ext.get("optionable") else "No", Decimal(1 if ext.get("optionable") else 0), None, None, "OPTIONS", date(2026, 8, 1), None, ext.get("notes")),
                            (run_id, scrip, assetclass, "StockAnalysis_20260801", "Options", "Premium ROI", ext.get("premium_roi_text"), ext.get("premium_roi"), ext.get("premium_roi"), ext.get("confidence_pct"), "OPTIONS", date(2026, 8, 1), None, ext.get("notes")),
                        ]
                    )
                if put:
                    external_rows.append((run_id, scrip, assetclass, "JStockGenieOptions", "Options", "Best SELL PUT", put.get("option_suitability"), put.get("premium_roi_pct"), put.get("recommendation_score"), put.get("probability_pct"), "OPTIONS", parse_yyyymmdd(put.get("signal_date")), None, "Best current put opportunity from jstockdata_reco_options."))
                if call:
                    external_rows.append((run_id, scrip, assetclass, "JStockGenieOptions", "Options", "Best SELL CALL", call.get("option_suitability"), call.get("premium_roi_pct"), call.get("recommendation_score"), call.get("probability_pct"), "OPTIONS", parse_yyyymmdd(call.get("signal_date")), None, "Best current call opportunity from jstockdata_reco_options."))
                if q:
                    external_rows.append((run_id, scrip, assetclass, "JStockGenieQuant", "Quality", "Quant Score", q.get("quant_analysis_rating"), q.get("quant_score"), q.get("quant_score"), q.get("quant_star_rating"), "MID_LONG", analysis_date, None, q.get("rating_reason")))

                risk_flag = "HIGH RISK" if risk_score >= 70 else "MEDIUM RISK" if risk_score >= 50 else "NORMAL"
                score_rows.append(
                    (
                        run_id,
                        scrip,
                        assetclass,
                        clip(short_score),
                        clip(mid_score),
                        clip(long_score),
                        clip(sell_put_score),
                        clip(sell_call_score),
                        investment_score,
                        clip(risk_score),
                        fusion_score,
                        confidence,
                        "v1",
                        "Fusion v1: trend/momentum core plus StockAnalysis, quant, and options confirmation.",
                    )
                )
                verdict_tuple = (
                    (
                        run_id,
                        scrip,
                        assetclass,
                        verdict_from_score(fusion_score),
                        verdict_from_score(short_score),
                        verdict_from_score(mid_score),
                        verdict_from_score(long_score),
                        suitability(clip(sell_put_score)),
                        suitability(clip(sell_call_score), "Covered Call Candidate"),
                        direction,
                        confidence,
                        risk_flag,
                        None,
                        "Use risk flag and current position context before trade execution.",
                    )
                )
                verdict_rows.append(verdict_tuple)
                score_lookup[(scrip, assetclass)] = {
                    "short": clip(short_score),
                    "mid": clip(mid_score),
                    "long": clip(long_score),
                    "sell_put": clip(sell_put_score),
                    "sell_call": clip(sell_call_score),
                    "investment": investment_score,
                    "risk": clip(risk_score),
                    "fusion": fusion_score,
                    "confidence": confidence,
                    "direction": direction,
                    "risk_flag": risk_flag,
                }
                verdict_lookup[(scrip, assetclass)] = {
                    "fusion_verdict": verdict_from_score(fusion_score),
                    "sell_put_suitability": suitability(clip(sell_put_score)),
                    "sell_call_suitability": suitability(clip(sell_call_score), "Covered Call Candidate"),
                }
                history_rows.append(
                    (
                        run_id,
                        scrip,
                        assetclass,
                        analysis_date,
                        fusion_score,
                        verdict_from_score(fusion_score),
                        direction,
                        confidence,
                        clip(short_score),
                        clip(mid_score),
                        clip(long_score),
                        clip(sell_put_score),
                        clip(sell_call_score),
                        investment_score,
                        clip(risk_score),
                        "Initial Fusion v1 snapshot.",
                    )
                )

            cur.executemany(
                """
                INSERT INTO jstockdata_fusion_internal_signal
                    (run_id, scrip, assetclass, daily_combined_signal, weekly_combined_signal,
                     daily_momentum, daily_confidence_pct, weekly_momentum, weekly_confidence_pct,
                     weekly_verdict, direction, direction_confidence_pct, signal_date, notes)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                internal_rows,
            )
            cur.executemany(
                """
                INSERT INTO jstockdata_fusion_external_signal
                    (run_id, scrip, assetclass, source_name, signal_category, signal_name,
                     signal_value, numeric_value, score, confidence_pct, timeframe, as_of_date,
                     source_url, notes)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                external_rows,
            )
            cur.executemany(
                """
                INSERT INTO jstockdata_fusion_score
                    (run_id, scrip, assetclass, short_term_score, mid_term_score, long_term_score,
                     sell_put_score, sell_call_score, investment_score, risk_score, fusion_score,
                     confidence_pct, score_version, notes)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                score_rows,
            )
            cur.executemany(
                """
                INSERT INTO jstockdata_fusion_verdict
                    (run_id, scrip, assetclass, fusion_verdict, short_term_verdict, mid_term_verdict,
                     long_term_verdict, sell_put_suitability, sell_call_suitability, direction,
                     confidence_pct, risk_flag, priority_rank, notes)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                verdict_rows,
            )
            cur.executemany(
                """
                INSERT INTO jstockdata_fusion_history
                    (run_id, scrip, assetclass, analysis_date, fusion_score, fusion_verdict,
                     direction, confidence_pct, short_term_score, mid_term_score, long_term_score,
                     sell_put_score, sell_call_score, investment_score, risk_score, notes)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                history_rows,
            )

            ranked = sorted(
                ((item[11], item[1], item[2]) for item in score_rows),
                reverse=True,
            )
            for rank, (_, scrip, assetclass) in enumerate(ranked, start=1):
                cur.execute(
                    """
                    UPDATE jstockdata_fusion_verdict
                    SET priority_rank = %s
                    WHERE run_id = %s AND scrip = %s AND assetclass = %s
                    """,
                    (rank, run_id, scrip, assetclass),
                )

            cur.execute(
                """
                SELECT broker, account_name, UPPER(scrip) AS scrip, segment, qty, avg_cost
                FROM jstockdata_current_positions
                WHERE scrip IS NOT NULL AND scrip <> ''
                """,
            )
            position_rows = []
            position_map = {}
            asset_by_scrip = {}
            for row in universe:
                asset_by_scrip.setdefault(row["scrip"], row["assetclass"])
            for pos in cur.fetchall():
                scrip = pos["scrip"]
                assetclass = asset_by_scrip.get(scrip, "EQ")
                pos_key = (pos["broker"], pos["account_name"], scrip, assetclass)
                qty = pos["qty"] or Decimal("0")
                avg_cost = pos["avg_cost"]
                if pos_key in position_map:
                    existing = position_map[pos_key]
                    existing_qty = existing["qty"] or Decimal("0")
                    new_qty = existing_qty + qty
                    if avg_cost is not None and existing["avg_cost"] is not None and new_qty != 0:
                        existing["avg_cost"] = (
                            (existing["avg_cost"] * existing_qty) + (avg_cost * qty)
                        ) / new_qty
                    elif avg_cost is not None:
                        existing["avg_cost"] = avg_cost
                    existing["qty"] = new_qty
                    if pos["segment"] and pos["segment"] not in existing["segments"]:
                        existing["segments"].append(pos["segment"])
                    continue
                position_map[pos_key] = {
                    "broker": pos["broker"],
                    "account_name": pos["account_name"],
                    "scrip": scrip,
                    "assetclass": assetclass,
                    "segments": [pos["segment"]] if pos["segment"] else [],
                    "qty": qty,
                    "avg_cost": avg_cost,
                }

            for pos in position_map.values():
                scrip = pos["scrip"]
                assetclass = pos["assetclass"]
                sc = score_lookup.get((scrip, assetclass), {})
                vd = verdict_lookup.get((scrip, assetclass), {})
                fusion_score = sc.get("fusion", 50)
                sell_call_score = sc.get("sell_call", 0)
                sell_put_score = sc.get("sell_put", 0)
                risk = sc.get("risk", 50)
                if fusion_score >= 70 and risk < 60:
                    action = "HOLD / ADD ON PULLBACK"
                elif fusion_score >= 55:
                    action = "HOLD / WATCH"
                elif fusion_score >= 42:
                    action = "HOLD / NO ADD"
                else:
                    action = "TRIM / REVIEW EXIT"
                option_action = "AVOID OPTIONS"
                if sell_call_score >= 70:
                    option_action = "SELL COVERED CALL CANDIDATE"
                elif sell_put_score >= 70:
                    option_action = "SELL PUT CANDIDATE"
                elif sell_call_score >= 55 or sell_put_score >= 55:
                    option_action = "OPTIONS WATCHLIST"
                position_rows.append(
                    (
                        run_id,
                        pos["broker"],
                        pos["account_name"],
                        scrip,
                        assetclass,
                        ",".join(pos["segments"])[:30] if pos["segments"] else None,
                        pos["qty"],
                        pos["avg_cost"],
                        None,
                        None,
                        None,
                        action,
                        option_action,
                        None,
                        None,
                        None,
                        sc.get("confidence"),
                        "%s; %s; risk=%s"
                        % (
                            vd.get("fusion_verdict", "WATCH"),
                            vd.get("sell_call_suitability", "No option verdict"),
                            sc.get("risk_flag", "UNKNOWN"),
                        ),
                    )
                )
            if position_rows:
                cur.executemany(
                    """
                    INSERT INTO jstockdata_fusion_position_action
                        (run_id, broker, account_name, scrip, assetclass, segment, qty, avg_cost,
                         position_value, current_price, unrealized_pl_pct, suggested_action,
                         option_action, target_entry, target_exit, target_stop, confidence_pct, notes)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                    """,
                    position_rows,
                )

            cur.execute(
                """
                UPDATE jstockdata_fusion_run
                SET status = 'COMPLETED', completed_at = NOW()
                WHERE run_id = %s
                """,
                (run_id,),
            )
            conn.commit()
            print(f"run_id={run_id}")
            print(f"base_universe={len(base_rows)}")
            print(f"internal_signal={len(internal_rows)}")
            print(f"external_signal={len(external_rows)}")
            print(f"score={len(score_rows)}")
            print(f"verdict={len(verdict_rows)}")
            print(f"position_action={len(position_rows)}")
            print(f"history={len(history_rows)}")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
