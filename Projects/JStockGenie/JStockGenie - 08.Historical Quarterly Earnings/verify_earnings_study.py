"""Independent standard-library checks of generated event and stock summaries."""
import csv
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent / 'earnings_study_20261022'


def read(name):
    with (ROOT/name).open(encoding='utf-8', newline='') as stream:
        return list(csv.DictReader(stream))


def main():
    events = read('SNP_Earnings_Event_Reactions.csv')
    summaries = read('SNP_Earnings_Trading_Approaches_By_Scrip.csv')
    meta = json.loads((ROOT/'analysis_metadata.json').read_text())
    assert len(events) == meta['matched_events']
    assert len(summaries) == meta['stocks']
    assert len(events)+len(read('SNP_Earnings_Excluded_Events.csv'))+meta['exact_duplicate_rows_removed'] == meta['input_rows']
    grouped = defaultdict(list)
    for r in events:
        grouped[r['symbol']].append(r)
        assert r['previous_date'] < r['reported_date'] < r['next_date']
        for output, numerator, denominator in (
            ('same_day_pct','report_close','prior_close'), ('next_day_pct','next_close','report_close'),
            ('two_session_pct','next_close','prior_close'), ('same_gap_pct','report_open','prior_close'),
            ('next_gap_pct','next_open','report_close'), ('carry_5session_pct','carry_exit_close','carry_entry_open')):
            if not r[output]:
                continue
            expected = (float(r[numerator])/float(r[denominator])-1)*100
            assert math.isclose(float(r[output]),expected,abs_tol=1e-9), (r['symbol'],r['reported_date'],output)
        if r['timing'] in ('BMO','AMC'):
            assert float(r['reaction_pct']) == float(r['same_day_pct' if r['timing']=='BMO' else 'next_day_pct'])
        if r['carry_entry_date']:
            assert r['next_date'] < r['carry_entry_date'] < r['carry_exit_date']
    for s in summaries:
        positive=[r for r in grouped[s['symbol']] if r['positive']=='True' and r['quality_flag']=='False']
        assert len(positive)==int(s['positive_n'])
        if positive:
            returns=[float(r['two_session_pct']) for r in positive]
            assert math.isclose(statistics.median(returns),float(s['positive_window_median_pct']),abs_tol=1e-9)
            assert math.isclose(100*sum(x>0 for x in returns)/len(returns),float(s['positive_window_up_pct']),abs_tol=1e-9)
        assert s['before_earnings'] and s['on_reaction_session'] and s['carry_after_earnings']
    report=(ROOT/'SNP_Earnings_Trading_Report.html').read_text(encoding='utf-8')
    assert report.count('class="stock"')==len(summaries)
    assert report.count('<details')==report.count('</details>')
    assert 'nan%' not in report and 'inf%' not in report
    print(f'PASS: {len(events)} event formulas, {len(summaries)} stock summaries, timing mapping, coverage reconciliation, and HTML sections.')


if __name__=='__main__':
    main()
