"""Daily OHLC proxy backtest for the Gap Trade Strategy. Read-only MySQL access."""
import csv
import os
import statistics
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path
from urllib.parse import unquote, urlsplit

import pymysql

ROOT = Path(__file__).resolve().parent
AS_OF = datetime.now().strftime("%Y%m%d")
OUT_TRADES = ROOT / f"Gap_Trade_Backtest_Trades_{AS_OF}.csv"
OUT_SCRIPS = ROOT / f"Gap_Trade_Backtest_By_Scrip_{AS_OF}.csv"
OUT_REPORT = ROOT / f"Gap_Trade_Backtest_Report_{AS_OF}.md"


def read_backtest_rows():
    raw = os.environ.get("MYSQL80_URL")
    if not raw:
        raise RuntimeError("MYSQL80_URL is not available")
    u = urlsplit(raw)
    if u.scheme not in ("mysql", "mysql+pymysql") or not u.hostname or not u.username or u.password is None:
        raise RuntimeError("MYSQL80_URL format is not supported")
    db = unquote(u.path.lstrip("/")) or "jstocksnp"
    conn = pymysql.connect(
        host=u.hostname, port=u.port or 3306, user=unquote(u.username),
        password=unquote(u.password), database=db, connect_timeout=10,
        read_timeout=60, autocommit=False, charset="utf8mb4"
    )
    try:
        with conn.cursor() as cur:
            cur.execute("SET TRANSACTION READ ONLY")
            conn.begin()
            cur.execute("""
                WITH hist_ranked AS (
                    SELECT scrip, `date`, `open`, high, low, close,
                           ROW_NUMBER() OVER (PARTITION BY scrip ORDER BY `date`) AS rn
                    FROM jstockdata_hist
                ), eligible AS (
                    SELECT g.gap_id, g.scrip, g.gap_date, g.prior_close,
                           g.gap_open, g.gap_direction, g.gap_pct, e.rn AS entry_rn
                    FROM jstockdata_gap_trades g
                    JOIN hist_ranked e ON e.scrip=g.scrip AND e.`date`=g.gap_date
                    WHERE ABS(g.gap_pct) BETWEEN 0.03 AND 0.19
                      AND g.gap_direction IN ('UP','DOWN')
                )
                SELECT e.gap_id, e.scrip, e.gap_date, e.prior_close, e.gap_open,
                       e.gap_direction, e.gap_pct, b.`date`, b.`open`, b.high,
                       b.low, b.close, (b.rn-e.entry_rn+1) AS session_no
                FROM eligible e
                JOIN hist_ranked b ON b.scrip=e.scrip
                    AND b.rn BETWEEN e.entry_rn AND e.entry_rn+9
                ORDER BY e.gap_id, session_no
            """)
            return cur.fetchall()
    finally:
        conn.rollback()
        conn.close()


def simulate(trade):
    """Return a 50/50 TP1/TP2 result, capped by gap fill and 10 sessions."""
    entry = trade["gap_open"]
    prior = trade["prior_close"]
    is_long = trade["gap_direction"] == "DOWN"
    if entry <= 0 or (is_long and prior <= entry) or (not is_long and prior >= entry):
        return None
    stop = entry * (0.99 if is_long else 1.01)
    tp1_raw = entry * (1.03 if is_long else 0.97)
    tp2_raw = entry * (1.05 if is_long else 0.95)
    # Gap fill is an additional profit exit; use whichever target is reached first.
    target1 = min(tp1_raw, prior) if is_long else max(tp1_raw, prior)
    target2 = min(tp2_raw, prior) if is_long else max(tp2_raw, prior)
    prior_precedes_tp1 = (prior <= tp1_raw) if is_long else (prior >= tp1_raw)
    legs = [1.0, 0.0] if prior_precedes_tp1 else [0.5, 0.5]
    active = [legs[0] > 0, legs[1] > 0]
    pnl = 0.0
    events = []
    exit_reason = None
    exit_date = None
    exit_session = None

    def favorable(price):
        return price - entry if is_long else entry - price

    def close_leg(index, price, label, date, session):
        nonlocal pnl, exit_reason, exit_date, exit_session
        if active[index]:
            pnl += legs[index] * favorable(price)
            active[index] = False
            events.append(f"{label}@{price:.4f} on {date}")
        if not any(active):
            exit_reason, exit_date, exit_session = label, date, session

    for session, date, op, hi, lo, cl in trade["bars"]:
        if not any(active):
            break
        remain = sum(legs[i] for i in range(2) if active[i])
        open_stop = (op <= stop) if is_long else (op >= stop)
        if open_stop:
            pnl += remain * favorable(op)
            events.append(f"stop_gap_open@{op:.4f} on {date}")
            exit_reason, exit_date, exit_session = "stop_gap_open", date, session
            break

        # Favorable opening gaps fill limit exits at the better opening price.
        open_target1 = (op >= target1) if is_long else (op <= target1)
        if active[0] and open_target1:
            label = "gap_fill" if prior_precedes_tp1 else "tp1"
            close_leg(0, op, label, date, session)
            if prior_precedes_tp1 and active[1]:
                close_leg(1, op, "gap_fill", date, session)
        open_target2 = (op >= target2) if is_long else (op <= target2)
        if active[1] and open_target2:
            close_leg(1, op, "gap_fill" if abs(target2-prior) < 1e-8 else "tp2", date, session)
        if not any(active):
            break

        hit_stop = (lo <= stop) if is_long else (hi >= stop)
        hit_t1 = active[0] and ((hi >= target1) if is_long else (lo <= target1))
        hit_t2 = active[1] and ((hi >= target2) if is_long else (lo <= target2))
        if hit_stop and (hit_t1 or hit_t2):
            remain = sum(legs[i] for i in range(2) if active[i])
            pnl += remain * favorable(stop)
            events.append(f"stop_same_bar_conservative@{stop:.4f} on {date}")
            exit_reason, exit_date, exit_session = "stop_same_bar_conservative", date, session
            break
        if hit_stop:
            remain = sum(legs[i] for i in range(2) if active[i])
            pnl += remain * favorable(stop)
            events.append(f"stop@{stop:.4f} on {date}")
            exit_reason, exit_date, exit_session = "stop", date, session
            break
        if active[0] and hit_t1:
            if prior_precedes_tp1:
                close_leg(0, target1, "gap_fill", date, session)
                if active[1]:
                    close_leg(1, target1, "gap_fill", date, session)
                break
            close_leg(0, target1, "tp1", date, session)
        if active[1] and hit_t2:
            label = "gap_fill" if abs(target2-prior) < 1e-8 else "tp2"
            close_leg(1, target2, label, date, session)
        if not any(active):
            break
        if session == 10:
            remain = sum(legs[i] for i in range(2) if active[i])
            pnl += remain * favorable(cl)
            events.append(f"session10_close@{cl:.4f} on {date}")
            exit_reason, exit_date, exit_session = "session10_close", date, session
            break

    stop_risk_per_share = entry * 0.01
    r_multiple = pnl / stop_risk_per_share
    return {
        **trade,
        "side": "LONG" if is_long else "SHORT",
        "entry_open_proxy": entry,
        "stop_price": stop,
        "tp1_price": tp1_raw,
        "tp2_price": tp2_raw,
        "gap_fill_price": prior,
        "exit_date": exit_date,
        "exit_session": exit_session,
        "exit_reason": exit_reason,
        "exit_events": "; ".join(events),
        "pnl_per_initial_share": pnl,
        "return_pct_on_position": 100 * pnl / entry,
        "R_multiple": r_multiple,
        "pnl_usd_if_each_trade_risked_100": 100 * r_multiple,
    }


def main():
    raw_rows = read_backtest_rows()
    grouped = {}
    for row in raw_rows:
        (gid, scrip, gap_date, prior, gap_open, direction, gap_pct,
         bar_date, op, hi, lo, cl, session) = row
        t = grouped.setdefault(gid, {
            "gap_id": gid, "scrip": scrip.strip(), "gap_date": int(gap_date),
            "prior_close": float(prior), "gap_open": float(gap_open),
            "gap_direction": direction.strip(), "gap_pct": float(gap_pct), "bars": []
        })
        t["bars"].append((int(session), int(bar_date), float(op), float(hi), float(lo), float(cl)))
    complete = [t for t in grouped.values() if len(t["bars"]) == 10]
    results = [r for t in complete if (r := simulate(t)) is not None]
    if not results:
        raise RuntimeError("No complete eligible trades were simulated")

    trade_fields = ["gap_id", "scrip", "gap_date", "gap_direction", "side", "gap_pct",
                    "entry_open_proxy", "prior_close", "stop_price", "tp1_price", "tp2_price",
                    "exit_date", "exit_session", "exit_reason", "exit_events",
                    "pnl_per_initial_share", "return_pct_on_position", "R_multiple",
                    "pnl_usd_if_each_trade_risked_100"]
    with OUT_TRADES.open("w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=trade_fields, extrasaction="ignore")
        w.writeheader(); w.writerows(results)

    by_symbol = defaultdict(list)
    for r in results:
        by_symbol[r["scrip"]].append(r)
    summaries = []
    for symbol, items in by_symbol.items():
        rs = [x["R_multiple"] for x in items]
        wins = sum(v > 0 for v in rs)
        losses = sum(v < 0 for v in rs)
        summaries.append({
            "scrip": symbol,
            "trades": len(items),
            "wins": wins,
            "losses": losses,
            "win_rate_pct": 100 * wins / len(items),
            "avg_R": statistics.mean(rs),
            "total_R": sum(rs),
            "normalized_pnl_usd_at_100_risk_each_trade": sum(x["pnl_usd_if_each_trade_risked_100"] for x in items),
            "avg_return_pct_on_position": statistics.mean(x["return_pct_on_position"] for x in items),
        })
    summaries.sort(key=lambda x: x["normalized_pnl_usd_at_100_risk_each_trade"], reverse=True)
    with OUT_SCRIPS.open("w", newline="", encoding="utf-8-sig") as f:
        fields = list(summaries[0].keys())
        w = csv.DictWriter(f, fieldnames=fields); w.writeheader(); w.writerows(summaries)

    n = len(results)
    all_r = [x["R_multiple"] for x in results]
    exits = Counter(x["exit_reason"] for x in results)
    wins = sum(x > 0 for x in all_r)
    direction_counts = Counter(x["side"] for x in results)
    asof = max(x["bars"][-1][1] for x in complete)
    first_date = min(x["gap_date"] for x in results)
    last_entry = max(x["gap_date"] for x in results)
    top = summaries[:10]
    bottom = list(reversed(summaries[-10:]))

    def md_table(items):
        lines = ["| Scrip | Trades | Win rate | Avg R | Total R | Normalized P&L* |",
                 "|---|---:|---:|---:|---:|---:|"]
        for x in items:
            lines.append(f"| {x['scrip']} | {x['trades']} | {x['win_rate_pct']:.1f}% | {x['avg_R']:.3f} | {x['total_R']:.2f} | ${x['normalized_pnl_usd_at_100_risk_each_trade']:,.2f} |")
        return "\n".join(lines)

    report = f'''# Gap Trade Strategy — Daily OHLC Proxy Backtest

**Run date:** {AS_OF}  
**Market data through:** {asof}  
**Gap entries simulated:** {n:,}  
**Entry dates:** {first_date}–{last_entry}  
**Database:** MySQL 8; `jstocksnp.jstockdata_gap_trades` joined to `jstockdata_hist`

## Headline result

- Wins: **{wins:,}/{n:,} ({wins/n:.2%})**; losses: **{n-wins:,}**.
- Mean outcome: **{statistics.mean(all_r):.3f} R/trade**; median: **{statistics.median(all_r):.2f} R**.
- Sum of independent trade outcomes: **{sum(all_r):.2f} R**, or **${sum(x['pnl_usd_if_each_trade_risked_100'] for x in results):,.2f}** if every trade independently risked $100.
- Exit reasons: {', '.join(f'{k} {v:,}' for k,v in exits.most_common())}.
- Sides: {direction_counts['LONG']:,} long and {direction_counts['SHORT']:,} short.

The normalized dollars are a per-trade comparison unit, **not an account-equity curve or a realized portfolio P&L**. The sum assumes a fresh $100 risk budget for every signal, ignores concurrent-position limits, overlap, compounding, and capital constraints.

## Method used

- Qualified `ABS(gap_pct)` from 3% through 19%, inclusive. This filter selected {len(grouped):,} records in the table; {len(grouped)-len(complete):,} recent records were omitted because ten full daily sessions of subsequent data were unavailable.
- User direction: gap up → short; gap down → long.
- **Entry proxy:** the gap-day daily open. The intended 9:45 a.m. ET price is not stored in the database, so the requested entry time cannot be reconstructed exactly.
- 1% adverse stop; TP#1 at 3% closes half; TP#2 at 5% closes the rest. The prior close is also treated as a take-profit, closing the remaining quantity if reached before the applicable percentage target.
- Entry session counts as session 1; any remaining shares exit at that session's close if session 10 is reached.
- Uses daily OHLC bars. If a bar touches both stop and a favorable target, assumes the stop happens first. If the market opens through the stop, uses the open as the exit price.
- Assumes fractional half-position accounting for the 50% scale-out. Results are gross of commissions, slippage, borrow costs, and taxes.

## Important limits

This is an **indicative daily-bar proxy**, not a faithful 9:45 intraday backtest. Daily bars include price movement before 9:45 on the entry day, and do not show the order of high/low events. They therefore cannot determine whether an intraday stop or target happened after entry, nor resolve same-bar event sequence. The proxy may misstate outcomes materially.

The data also does not provide historical short availability, the unresolved trailing-stop alternative was not modeled, no separate cumulative daily loss cap was applied, and no historical ranking rule was available to select at most 10 simultaneous positions. Each signal was evaluated independently. Do not treat the results as validated strategy performance or use them as a live-trading forecast.

## Best 10 scrips by normalized P&L*

{md_table(top)}

## Worst 10 scrips by normalized P&L*

{md_table(bottom)}

* Normalized P&L assumes $100 risk per individual trade. Full 600-scrip results are in `{OUT_SCRIPS.name}`; trade-level calculations are in `{OUT_TRADES.name}`.
'''
    OUT_REPORT.write_text(report, encoding="utf-8")
    print(f"SIMULATED={n}")
    print(f"ENTRY_DATES={first_date}-{last_entry}; BARS_THROUGH={asof}")
    print(f"WIN_RATE={wins/n:.4%}; MEAN_R={statistics.mean(all_r):.4f}; MEDIAN_R={statistics.median(all_r):.4f}; SUM_R={sum(all_r):.2f}")
    print(f"NORMALIZED_PNL_AT_100_RISK_PER_SIGNAL=${sum(x['pnl_usd_if_each_trade_risked_100'] for x in results):,.2f}")
    print("EXIT_COUNTS=" + str(dict(exits)))
    print("TOP10:")
    for x in top: print(f"{x['scrip']}\t{x['trades']}\t{x['win_rate_pct']:.1f}%\t{x['avg_R']:.3f}R\t${x['normalized_pnl_usd_at_100_risk_each_trade']:,.2f}")
    print("BOTTOM10:")
    for x in bottom: print(f"{x['scrip']}\t{x['trades']}\t{x['win_rate_pct']:.1f}%\t{x['avg_R']:.3f}R\t${x['normalized_pnl_usd_at_100_risk_each_trade']:,.2f}")
    print("OUTPUTS:")
    print(OUT_REPORT)
    print(OUT_SCRIPS)
    print(OUT_TRADES)

if __name__ == "__main__":
    main()



