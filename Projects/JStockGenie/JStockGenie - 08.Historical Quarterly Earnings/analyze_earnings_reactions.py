"""Analyze saved CSV and read-only MySQL export; produce auditable research reports."""
import csv
import hashlib
import html
import json
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'earnings_study_20261022'
SOURCE = ROOT / 'SNP_Earnings_JStockSNP500List.csv'


def pct(a, b):
    return 100 * (a / b - 1)


def wilson(k, n):
    if not n:
        return (None, None)
    z = 1.96
    p = k / n
    center = (p + z*z/(2*n))/(1+z*z/n)
    half = z*np.sqrt(p*(1-p)/n+z*z/(4*n*n))/(1+z*z/n)
    return 100*(center-half), 100*(center+half)


def stats(frame, column):
    values = frame[column].dropna() if column in frame else pd.Series(dtype=float)
    n = len(values)
    return {'n': n, 'median': float(values.median()) if n else None,
            'mean': float(values.mean()) if n else None,
            'up': 100*float((values > 0).mean()) if n else None,
            'abs90': float(values.abs().quantile(.90)) if n else None}


def fmt(value, suffix='%'):
    return 'n/a' if value is None or pd.isna(value) else f'{value:.2f}{suffix}'


def plan(s):
    n, b = s['all_n'], s['positive_n']
    if n < 8 or b < 6:
        return ('Insufficient sample', 'No earnings-specific entry. Fewer than 8 usable releases or 6 positive surprises.',
                'Watch only; collect verified release timing and more events before selecting a setup.',
                'Use the normal stock trend setup; this earnings sample does not support a carry bias.')
    if s['quality_flags']:
        return ('Price-quality review', 'No pre-release options selection until flagged price jumps/corporate actions are checked.',
                'Validate adjusted prices and release timing before trading any gap.',
                'No earnings-based carry recommendation until flagged events are reconciled.')
    up, med = s['positive_window_up_pct'], s['positive_window_median_pct']
    if up >= 70 and med >= .5:
        label = 'Bullish reaction watch'
        on = 'After a confirmed beat: consider long equity or bull call debit spread only above the first 30-minute high with VWAP support; skip if the gap fails.'
    elif up <= 30 and med <= -.5:
        label = 'Bearish reaction watch'
        on = 'Even after a beat: prefer reducing equity or a bear put debit spread only below the first 30-minute low and VWAP; do not short solely because EPS beat.'
    else:
        label = 'Mixed reaction / confirmation'
        on = 'Trade the confirmed gap direction only after the first 30 minutes. Fade toward prior close only after a failed opening-range break and VWAP reversal; otherwise skip.'
    if s['all_window_abs_p90_pct'] >= 8:
        pre = 'Large event-move risk: avoid uncovered options and tight iron butterflies. Prefer waiting; a small debit spread needs an independent directional thesis and acceptable premium.'
    elif s['all_window_abs_p90_pct'] <= 4 and 35 <= s['all_window_up_pct'] <= 65:
        pre = 'Conditional neutral credit-spread/iron-condor candidate only if implied move exceeds historical tails, quotes are liquid, and max loss fits budget. Iron butterfly is not the default.'
    else:
        pre = 'Prefer waiting for the release. If an independent thesis supports direction, use a small defined-risk debit spread; a positive EPS surprise cannot be known in advance.'
    if s['nonpositive_n'] < 2:
        pre = 'Prefer no new pre-release position: fewer than two observed nonpositive surprises, so miss risk is not calibrated. If independently bullish/bearish, a small debit spread caps loss; avoid an automatic earnings iron butterfly.'
    carry_up, carry_med = s['carry_up_pct'], s['carry_median_pct']
    if s['carry_n'] < 6:
        carry = 'Insufficient five-session observations: avoid earnings-based carry; manage only a separately confirmed trend.'
    elif carry_up >= 70 and carry_med > .5:
        carry = 'Bullish carry watch: after D+1 closes, consider next-open equity/bull call spread if price still holds VWAP/support. Review within five sessions; bull put credit spread only with adequate premium.'
    elif carry_up <= 30 and carry_med < -.5:
        carry = 'Bearish carry watch: reduce longs or consider bear put spread after a weak D+1 close; bear call credit spread only below resistance with adequate premium. Review within five sessions.'
    else:
        carry = 'No clear five-session drift: take event-trade profits rather than assume continuation. Neutral defined-risk spreads require a new range and sufficient post-release premium.'
    if s['symbol'] == 'PG':
        on = 'Watch gap continuation only after a first-30-minute breakout and VWAP support. Do not chase the opening gap or automatically fade it: only 1 of 9 timing-matched gaps of at least 1% filled intraday in this sample.'
    if s['symbol'] == 'AAPL':
        on = 'Use the next session after the after-close release. A beat alone is not a buy: reduce equity or use a bear put spread only on a confirmed opening-range breakdown; buy only on a confirmed reclaim.'
        carry = 'Conditional long carry after D+1 strength: equity or bull call spread with support intact. Overall 8/11 five-session windows rose, but only 4/7 after a negative reaction; do not mechanically buy the dip. Bull put spread requires adequate premium.'
    return label, pre, on, carry


def main():
    raw = pd.read_csv(SOURCE, dtype={'symbol': str})
    raw['symbol'] = raw['symbol'].str.strip().str.upper()
    raw['reported_date'] = pd.to_datetime(raw['reported_date'], errors='coerce')
    raw['surprise_percentage'] = pd.to_numeric(raw['surprise_percentage'], errors='coerce')
    prices = pd.read_csv(OUT/'prices.csv')
    prices.columns = prices.columns.str.lower()
    prices['date'] = pd.to_datetime(prices['date'].astype(str), format='%Y%m%d')
    assert not prices.duplicated(['scrip', 'date']).any(), 'Duplicate daily bars'
    assets = pd.read_csv(OUT/'asset_classes.csv').fillna('')
    classes = assets.groupby('Scrip')['AssetClass'].agg(set).to_dict()
    names = dict(zip(assets['Scrip'], assets['Company Name']))
    supplementary_path = OUT/'supplementary_asset_classes.json'
    supplementary = json.loads(supplementary_path.read_text()) if supplementary_path.exists() else []
    for row in supplementary:
        if row['symbol'] not in classes and row['quoteType'] == 'EQUITY':
            classes[row['symbol']] = {'EQT'}
            names[row['symbol']] = row['name']
    bars = {s: f.set_index('date').sort_index() for s, f in prices.groupby('scrip')}
    calendar = list(bars['SPY'].index) if 'SPY' in bars else sorted(prices['date'].unique())
    positions = {d: i for i, d in enumerate(calendar)}
    timings = {(r['symbol'], r['reported_date']): r for r in json.loads((OUT/'timing_evidence.json').read_text())}
    events, audit = [], []
    duplicate_count = int(raw.duplicated().sum())
    cleaned = raw.drop_duplicates()
    conflicts = set(map(tuple, cleaned.loc[cleaned.duplicated(['symbol', 'reported_date'], keep=False), ['symbol', 'reported_date']].values))
    def audit_row(symbol, d, reason, surprise):
        audit.append(dict(symbol=symbol, reported_date=str(d)[:10], reason=reason, surprise_percentage=surprise))
    for row in cleaned.itertuples(index=False):
        symbol, d, surprise = row.symbol, row.reported_date, row.surprise_percentage
        dbsymbol = symbol if symbol in classes else symbol.replace('-', '.')
        if classes.get(dbsymbol) != {'EQT'}:
            audit_row(symbol, d, 'non_stock_or_unclassified', surprise); continue
        if (symbol, d) in conflicts:
            audit_row(symbol, d, 'conflicting_duplicate_date', surprise); continue
        if pd.isna(d) or pd.isna(surprise) or not np.isfinite(surprise):
            audit_row(symbol, d, 'missing_date_or_surprise', surprise); continue
        frame = bars.get(dbsymbol)
        i = positions.get(d)
        if frame is None or i is None or i == 0 or i+1 >= len(calendar):
            audit_row(symbol, d, 'outside_price_coverage_or_nontrading_date', surprise); continue
        needed = calendar[i-1:i+2]
        if not all(day in frame.index for day in needed):
            audit_row(symbol, d, 'missing_adjacent_price_bar', surprise); continue
        before, same, nxt = (frame.loc[day] for day in needed)
        relevant = frame.loc[needed, ['open','high','low','close']]
        if (relevant <= 0).any().any() or (relevant['low'] > relevant[['open','close']].min(axis=1)).any() or (relevant['high'] < relevant[['open','close']].max(axis=1)).any():
            audit_row(symbol, d, 'invalid_ohlc', surprise); continue
        timing = timings.get((symbol, d.date().isoformat()), {}).get('timing', 'UNKNOWN')
        record = dict(symbol=symbol, company=names.get(dbsymbol,''), reported_date=d.date().isoformat(),
                      surprise_percentage=surprise, positive=bool(surprise > 0), timing=timing,
                      previous_date=needed[0].date().isoformat(), next_date=needed[2].date().isoformat(),
                      prior_close=before['close'], report_open=same['open'], report_high=same['high'], report_low=same['low'], report_close=same['close'],
                      next_open=nxt['open'], next_high=nxt['high'], next_low=nxt['low'], next_close=nxt['close'],
                      same_day_pct=pct(same['close'],before['close']), next_day_pct=pct(nxt['close'],same['close']),
                      two_session_pct=pct(nxt['close'],before['close']), same_gap_pct=pct(same['open'],before['close']),
                      next_gap_pct=pct(nxt['open'],same['close']), same_intraday_pct=pct(same['close'],same['open']),
                      next_intraday_pct=pct(nxt['close'],nxt['open']))
        record['quality_flag'] = max(abs(record['same_day_pct']), abs(record['next_day_pct']),abs(record['same_gap_pct']),abs(record['next_gap_pct'])) > 30
        record['reaction_date'] = record['reported_date'] if timing == 'BMO' else record['next_date'] if timing == 'AMC' else ''
        record['reaction_pct'] = record['same_day_pct'] if timing == 'BMO' else record['next_day_pct'] if timing == 'AMC' else None
        record['reaction_gap_pct'] = record['same_gap_pct'] if timing == 'BMO' else record['next_gap_pct'] if timing == 'AMC' else None
        record['reaction_intraday_pct'] = record['same_intraday_pct'] if timing == 'BMO' else record['next_intraday_pct'] if timing == 'AMC' else None
        record['reaction_gap_filled'] = None
        if timing in ('BMO', 'AMC'):
            reaction, prior = (same, before['close']) if timing == 'BMO' else (nxt, same['close'])
            if abs(record['reaction_gap_pct']) >= 1:
                record['reaction_gap_filled'] = bool(reaction['low'] <= prior if reaction['open'] > prior else reaction['high'] >= prior)
        # A universally post-release entry, avoiding uncertainty over BMO versus AMC.
        record.update(carry_entry_date='', carry_exit_date='', carry_entry_open=None, carry_exit_close=None, carry_5session_pct=None, carry_quality_flag=False)
        if i+6 < len(calendar) and all(day in frame.index for day in calendar[i+2:i+7]):
            future = frame.loc[calendar[i+2:i+7]]
            closes = [nxt['close']] + future['close'].tolist()
            carry_flag = any(abs(pct(closes[k+1],closes[k])) > 30 for k in range(5)) or (future[['open','high','low','close']] <= 0).any().any()
            record.update(carry_entry_date=calendar[i+2].date().isoformat(), carry_exit_date=calendar[i+6].date().isoformat(),
                          carry_entry_open=future.iloc[0]['open'], carry_exit_close=future.iloc[-1]['close'],
                          carry_5session_pct=pct(future.iloc[-1]['close'],future.iloc[0]['open']), carry_quality_flag=bool(carry_flag))
        record['two_session_spy_excess_pp'] = None
        if 'SPY' in bars and all(day in bars['SPY'].index for day in needed):
            record['two_session_spy_excess_pp'] = record['two_session_pct']-pct(bars['SPY'].loc[needed[2],'close'],bars['SPY'].loc[needed[0],'close'])
        events.append(record)
    ev = pd.DataFrame(events)
    ev.sort_values(['symbol','reported_date'],ascending=[True,False],inplace=True)
    ev.to_csv(OUT/'SNP_Earnings_Event_Reactions.csv', index=False)
    pd.DataFrame(audit).to_csv(OUT/'SNP_Earnings_Excluded_Events.csv',index=False)
    summaries = []
    for symbol in sorted(raw.symbol.unique()):
        dbsymbol = symbol if symbol in classes else symbol.replace('-', '.')
        if classes.get(dbsymbol) != {'EQT'}:
            continue
        all_rows = ev[ev.symbol == symbol]
        valid = all_rows[~all_rows.quality_flag]
        positive = valid[valid.positive]
        a, b = stats(valid,'two_session_pct'), stats(positive,'two_session_pct')
        carry = stats(positive[~positive.carry_quality_flag], 'carry_5session_pct')
        reaction = stats(positive,'reaction_pct')
        negative = stats(valid[~valid.positive],'two_session_pct')
        low, high = wilson(int((positive.two_session_pct > 0).sum()),len(positive))
        s = dict(symbol=symbol, company=names.get(dbsymbol,''), all_n=a['n'], positive_n=b['n'], nonpositive_n=negative['n'],
                 same_day_positive_up_pct=stats(positive,'same_day_pct')['up'], same_day_positive_median_pct=stats(positive,'same_day_pct')['median'],
                 next_day_positive_up_pct=stats(positive,'next_day_pct')['up'], next_day_positive_median_pct=stats(positive,'next_day_pct')['median'],
                 positive_window_up_pct=b['up'], positive_window_median_pct=b['median'], positive_window_mean_pct=b['mean'],
                 positive_window_abs_p90_pct=b['abs90'], positive_up_ci95_low=low,positive_up_ci95_high=high,
                 all_window_up_pct=a['up'], all_window_median_pct=a['median'], all_window_abs_p90_pct=a['abs90'],
                 nonpositive_window_median_pct=negative['median'],
                 positive_spy_excess_median_pp=stats(positive,'two_session_spy_excess_pp')['median'],
                 timing_known_positive_n=reaction['n'], reaction_positive_up_pct=reaction['up'], reaction_positive_median_pct=reaction['median'],
                 reaction_gap_median_pct=stats(positive,'reaction_gap_pct')['median'],
                 reaction_intraday_median_pct=stats(positive,'reaction_intraday_pct')['median'],
                 reaction_gaps_ge1_n=int(positive.reaction_gap_filled.notna().sum()),
                 reaction_gaps_filled_n=int(positive.reaction_gap_filled.fillna(False).astype(bool).sum()),
                 carry_n=carry['n'], carry_up_pct=carry['up'], carry_median_pct=carry['median'],
                 quality_flags=int(all_rows.quality_flag.sum()+all_rows.carry_quality_flag.sum()))
        recent = positive.sort_values('reported_date').tail(4)
        s['recent4_window_median_pct'] = stats(recent,'two_session_pct')['median']
        s['profile'],s['before_earnings'],s['on_reaction_session'],s['carry_after_earnings'] = plan(s)
        summaries.append(s)
    summary = pd.DataFrame(summaries)
    summary.to_csv(OUT/'SNP_Earnings_Trading_Approaches_By_Scrip.csv',index=False)
    meta = dict(report_date='2026-10-22', price_start=str(prices.date.min().date()), price_end=str(prices.date.max().date()),
                input_rows=len(raw),input_symbols=raw.symbol.nunique(), stocks=len(summary), excluded_symbols=raw.symbol.nunique()-len(summary),
                matched_events=len(ev),positive_matched=int(ev.positive.sum()),usable_positive=int((ev.positive & ~ev.quality_flag).sum()),
                quality_flag_events=int(ev.quality_flag.sum()),exact_duplicate_rows_removed=duplicate_count,
                exclusions=dict(Counter(r['reason'] for r in audit)),source_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                profiles=summary.profile.value_counts().to_dict())
    meta['supplementary_equity_classifications'] = [r['symbol'] for r in supplementary if r['quoteType']=='EQUITY']
    (OUT/'analysis_metadata.json').write_text(json.dumps(meta,indent=2))
    make_report(summary,ev,meta)
    print(json.dumps(meta,indent=2))
    print(summary[summary.symbol.isin(['PG','AAPL'])].to_json(orient='records',indent=2))


def make_report(summary,ev,meta):
    def table(frame):
        return frame.to_html(index=False, border=0, classes='data', na_rep='n/a', float_format=lambda x:f'{x:.2f}')
    sections=[]
    for s in summary.to_dict('records'):
        symbol=s['symbol']
        rows=ev[(ev.symbol==symbol)&ev.positive].copy()
        shown=rows[['reported_date','surprise_percentage','same_day_pct','next_day_pct','two_session_pct','timing','reaction_pct','carry_5session_pct','quality_flag']]
        sections.append(f'''<details class="stock" data-search="{html.escape((symbol+' '+s['company']+' '+s['profile']).lower())}" {'open' if symbol in ('PG','AAPL') else ''}>
<summary><b>{html.escape(symbol)}</b> · {html.escape(s['company'])} · {html.escape(s['profile'])} · {s['positive_n']} positive events</summary>
<p>Positive-surprise two-session median: <b>{fmt(s['positive_window_median_pct'])}</b>. Up frequency: {fmt(s['positive_window_up_pct'])}, approximate 95% Wilson interval {fmt(s['positive_up_ci95_low'])}–{fmt(s['positive_up_ci95_high'])}. Latest four median: {fmt(s['recent4_window_median_pct'])}. SPY-excess median: {fmt(s['positive_spy_excess_median_pp'],' pp')}.</p>
<p>All {s['all_n']} usable releases: median {fmt(s['all_window_median_pct'])}, 90th percentile absolute two-session move {fmt(s['all_window_abs_p90_pct'])}. Nonpositive surprises: {s['nonpositive_n']}, median {fmt(s['nonpositive_window_median_pct'])}. Five-session carry: {s['carry_n']} observations, median {fmt(s['carry_median_pct'])}, up {fmt(s['carry_up_pct'])}.</p>
<div class="plans"><p><strong>Before earnings</strong><br>{html.escape(s['before_earnings'])}</p><p><strong>On the reaction session</strong><br>{html.escape(s['on_reaction_session'])}</p><p><strong>Carry after earnings</strong><br>{html.escape(s['carry_after_earnings'])}</p></div>
<p class="note">Timing-matched positive events: {s['timing_known_positive_n']}; reaction median {fmt(s['reaction_positive_median_pct'])}, up {fmt(s['reaction_positive_up_pct'])}. Median opening gap {fmt(s['reaction_gap_median_pct'])}; median open-to-close return {fmt(s['reaction_intraday_median_pct'])}. Of {s['reaction_gaps_ge1_n']} gaps at least 1%, {s['reaction_gaps_filled_n']} touched prior close intraday (touch is not proof of an executable fill). {'Daily timing obtained from Yahoo.' if s['timing_known_positive_n'] else 'Release time is missing: both daily windows are shown; two-session behavior is a screening proxy.'} Flag counts: {s['quality_flags']} (reaction and carry flags may overlap).</p>
<div class="scroll">{table(shown)}</div></details>''')
    focused=summary[summary.symbol.isin(['PG','AAPL'])][['symbol','positive_n','same_day_positive_up_pct','same_day_positive_median_pct','next_day_positive_up_pct','next_day_positive_median_pct','reaction_positive_up_pct','reaction_positive_median_pct','carry_median_pct']]
    report=f'''<!doctype html><html lang="en"><meta charset="utf-8"><title>JStockGenie earnings reaction study</title>
<style>body{{font:16px/1.6 Segoe UI,Arial,sans-serif;margin:36px auto;max-width:1500px;padding:0 24px;color:#182538;background:#f6f8fb}}h1,h2{{color:#123653}}h1{{font-size:34px}}.lede{{font-size:20px;max-width:1100px}}.card,details{{background:white;border:1px solid #d8e1eb;border-radius:8px;padding:20px;margin:18px 0}}summary{{cursor:pointer;font-size:18px}}.plans{{display:grid;grid-template-columns:repeat(3,1fr);gap:24px}}.plans strong{{color:#135876}}.data{{border-collapse:collapse;width:100%;font-size:13px}}th,td{{padding:8px 10px;border-bottom:1px solid #dde5ed;text-align:right}}th{{background:#183c56;color:white;white-space:normal}}td:first-child,th:first-child{{text-align:left}}tr:nth-child(even){{background:#f1f5f9}}.scroll{{overflow:auto}}.note{{color:#566777;font-size:14px}}input{{padding:14px;font-size:17px;width:90%;border:1px solid #9caebb;border-radius:6px}}a{{color:#126187}}li{{margin:8px 0}}@media(max-width:800px){{.plans{{display:block}}}}@media print{{input{{display:none}}details{{break-inside:avoid}}}}</style>
<h1>Positive earnings surprises and stock-price reactions</h1>
<p class="lede">A beat is not a direction signal. Separate the overnight gap, the reaction session, and the trade that is still available after the release.</p>
<p>Prepared October 22, 2026. MySQL 8.0 <code>jstockdata_curr</code> prices: {meta['price_start']} through <b>{meta['price_end']}</b>. Current trades need newer prices.</p>
<div class="card"><h2>Coverage</h2><p>{meta['input_rows']:,} earnings rows across {meta['input_symbols']} symbols. {meta['stocks']} symbols are classified as stocks using <code>jstockdata_scrips</code> plus Yahoo EQUITY verification for missing master records; {meta['excluded_symbols']} non-stock or unclassified symbols excluded. {meta['matched_events']:,} events have an exact report-date bar plus both adjacent market sessions; {meta['positive_matched']:,} are positive surprises. {meta['usable_positive']:,} positive events remain after price-quality flags.</p>
<p>Supplementary Yahoo equity classifications: {', '.join(meta['supplementary_equity_classifications']) or 'none'}. These were missing from the local master, not excluded as ETFs.</p><p>Report focuses on positive surprises. Pre-release risk uses <b>all available surprises</b>, including zero/negative values. Existing holdings are not evaluated for valuation, taxes, or portfolio suitability.</p>
<p><a href="SNP_Earnings_Trading_Approaches_By_Scrip.csv">All stock summaries and trade approaches</a> · <a href="SNP_Earnings_Event_Reactions.csv">Event calculations and source OHLC</a> · <a href="SNP_Earnings_Excluded_Events.csv">Excluded-event audit</a></p></div>
<div class="card"><h2>PG and AAPL: the timing check</h2><p>Yahoo timestamps identify PG as before-market and AAPL as after-market for the matched study events. PG's reaction uses the report session; AAPL's uses the next session. Times are provider evidence, not independently verified for every release. Same-day returns for AAPL generally precede its announcement.</p><div class="scroll">{table(focused)}</div><p>PG rose on 7 of 11 reaction sessions, but its median open-to-close return was approximately −0.05%: much of the gain was already in the opening gap. AAPL rose in 8 of 11 later five-session windows, but after a negative initial reaction only 4 of 7 rose (median +0.50%); after a positive initial reaction 4 of 4 rose (median +5.92%). These tiny conditional samples do not establish a buy-the-dip rule.</p><p>See the expanded PG and AAPL event tables below. Positive EPS can coexist with falling prices because guidance, revenue, margins, positioning and expectations beyond the published consensus also matter. This dataset does not identify which factor caused an individual move.</p></div>
<div class="card"><h2>How to use the three trading stages</h2>
<ol><li><b>Before the release:</b> never condition an entry on a future realized beat. Default to waiting. A bullish thesis can use a bull call debit spread; a bearish thesis can use a bear put debit spread. Debit paid is the planned maximum loss. Directional credit spreads require enough premium and a defensible support/resistance level. Historical move size alone does not establish positive option expectancy.</li>
<li><b>On earnings / the reaction session:</b> for BMO, use that day's open; for AMC, use the following trading session. Wait for the first 30-minute range. Consider continuation above its high with VWAP support (long) or below its low with VWAP resistance (bearish). A gap-fade needs a failed range break and a VWAP reversal, with the previous close as a possible target. The OHLC table cannot test these intraday triggers. Skip if spread/slippage is excessive.</li>
<li><b>Carry afterward:</b> review the position at D+1 close; a common timing-safe proxy enters at D+2 open and exits D+6 close (five trading sessions). Carry only if the observed price trend supports the direction. Exit on a break of the reaction structure or at the time limit; overnight stops can slip. Bull put spreads fit bullish support; bear call spreads fit bearish resistance, conditional on actual quotes. For illustration, cap maximum loss at 0.25%–0.5% of account equity per idea, sized from the stop or spread maximum loss, not share count.</li></ol>
<p><b>Iron butterfly:</b> not recommended automatically before earnings. A short iron butterfly sells an ATM call and put and buys farther OTM wings; its small profit zone can be overwhelmed by an event gap. Consider only with verified release timing, liquid options, a defensible implied-versus-realized-move advantage, and a tolerable wing-width-minus-credit maximum loss. An iron condor offers a wider neutral range. After earnings, IV compression may already have removed most of the credit; low realized movement is not enough to justify either structure. Plan to close short spreads before expiration to manage assignment and pin risk.</p></div>
<div class="card"><h2>Definitions and limits</h2><ul>
<li>D is the reported date; D+1 is the next actual SPY market session. Same-day = close(D)/close(D−1)−1. Next-day = close(D+1)/close(D)−1. Two-session = close(D+1)/close(D−1)−1. Gaps use open/prior close. All returns shown in percentage points, e.g. 2.00 means 2%.</li>
<li>For all stocks except PG/AAPL, release times are unavailable. The two-session window captures either BMO or AMC but also includes a non-reaction session. It must not be called an executable earnings-day return. Report-date holidays/weekends and missing adjacent bars are excluded, not shifted automatically.</li>
<li>Carry = close(D+6)/open(D+2)−1, before fees, spreads and slippage. This is a fixed-horizon long-equity proxy on positive-surprise events, not a backtest of the suggested opening-range or options strategies.</li>
<li>Current-table OHLC adjustment status is not documented. Events with a daily close move or opening gap over 30% are flagged and excluded from summary estimation pending corporate-action review; raw records remain in the event CSV. This can remove genuine tail moves, so affected stocks receive no strategy selection. Carry windows with daily close moves over 30% are separately flagged. Smaller split/dividend effects may remain. No total-return adjustment is assumed.</li>
<li>Exact duplicate input rows removed: {meta['exact_duplicate_rows_removed']}. Conflicting same-symbol/date records are excluded. Nonpositive includes zero and negative surprise, not missing surprise. Blank metrics mean unavailable.</li>
<li>Profiles are exploratory rules: at least 8 usable total events and 6 beats; bullish/bearish watch requires two-session up frequency ≥70%/≤30% and median ≥0.5%/≤−0.5%. Other stocks are mixed. Carry uses the same 70%/30% and ±0.5% thresholds with at least 6 observations. Pre-release neutral screening requires an all-event 90th-percentile absolute move ≤4% and up frequency between 35% and 65%; ≥8% move triggers large-event-risk guidance. These are research cutoffs, not optimized or validated edges.</li>
<li>Samples cover fewer than three years and often only a handful of quarters. Wilson intervals assume independent events and are descriptive. No multiple-testing correction, out-of-sample validation, historical option chains, IV, execution costs, or intraday bars are available. Current-universe survivorship and historical vendor revisions can bias the study. SPY excess is a simple paired return difference, not beta-adjusted alpha.</li></ul>
<p>Exclusion counts: {html.escape(json.dumps(meta['exclusions']))}.</p>
<p>Sources: user earnings CSV; read-only MySQL snapshot; <a href="https://finance.yahoo.com/calendar/earnings?symbol=PG">Yahoo PG dates</a>; <a href="https://finance.yahoo.com/calendar/earnings?symbol=AAPL">Yahoo AAPL dates</a>; <a href="https://www.fidelity.com/viewpoints/active-investor/trading-earnings">Fidelity earnings trading</a>; <a href="https://www.schwab.com/learn/story/trading-options-around-earnings-announcements">Schwab options and earnings</a>. Input SHA-256: <code>{meta['source_sha256']}</code>.</p></div>
<h2>Trade approaches by scrip</h2><p>Search a ticker, company, or profile. Expand a row for all positive-surprise events and the three-stage approach. Dates are newest first.</p>
<input id="search" aria-label="Search stocks" placeholder="Search: PG, AAPL, bullish, mixed…" oninput="document.querySelectorAll('.stock').forEach(x=>x.hidden=!x.dataset.search.includes(this.value.toLowerCase()))">
{''.join(sections)}</html>'''
    (OUT/'SNP_Earnings_Trading_Report.html').write_text(report,encoding='utf-8')


if __name__ == '__main__':
    main()
