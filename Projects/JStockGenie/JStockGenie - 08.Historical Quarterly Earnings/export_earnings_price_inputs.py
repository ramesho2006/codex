"""Read-only MySQL snapshot and Yahoo timing evidence for the earnings study."""
import csv
import json
import os
import ssl
import tempfile
from pathlib import Path
from urllib.parse import unquote, urlsplit

import pymysql

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'earnings_study_20261022'


def main():
    OUT.mkdir(exist_ok=True)
    u = urlsplit(os.environ['MYSQL80_URL'])
    conn = pymysql.connect(host=u.hostname, port=u.port or 3306, user=unquote(u.username),
                           password=unquote(u.password), database=unquote(u.path.lstrip('/')) or 'jstocksnp',
                           connect_timeout=10, read_timeout=120)
    try:
        with conn.cursor() as cursor:
            cursor.execute('SET TRANSACTION READ ONLY')
            conn.begin()
            for filename, sql in [
                ('asset_classes.csv', 'SELECT Scrip, `Company Name`, AssetClass FROM jstockdata_scrips ORDER BY Scrip'),
                ('prices.csv', 'SELECT SCRIP, DATE, OPEN, HIGH, LOW, CLOSE FROM jstockdata_curr ORDER BY SCRIP, DATE')]:
                cursor.execute(sql)
                with (OUT / filename).open('w', newline='', encoding='utf-8') as stream:
                    writer = csv.writer(stream)
                    writer.writerow([column[0] for column in cursor.description])
                    writer.writerows(cursor.fetchall())
    finally:
        conn.rollback()
        conn.close()
    import certifi
    import yfinance as yf
    from curl_cffi import requests
    timings = []
    classifications = []
    with tempfile.TemporaryDirectory() as directory:
        bundle = Path(directory) / 'ca.pem'
        certificates = Path(certifi.where()).read_text()
        if os.name == 'nt':
            for store in ('ROOT', 'CA'):
                for certificate, encoding, trust in ssl.enum_certificates(store):
                    if encoding == 'x509_asn' and (trust is True or '1.3.6.1.5.5.7.3.1' in trust):
                        certificates += '\n' + ssl.DER_cert_to_PEM_cert(certificate)
        bundle.write_text(certificates)
        with requests.Session(impersonate='chrome', verify=str(bundle)) as session:
            with (ROOT/'SNP_Earnings_JStockSNP500List.csv').open() as stream:
                symbols = {r['symbol'] for r in csv.DictReader(stream)}
            with (OUT/'asset_classes.csv').open() as stream:
                classified = {r['Scrip'] for r in csv.DictReader(stream)}
            for symbol in sorted(symbols-classified):
                try:
                    quotes = yf.Search(symbol, max_results=1, session=session).quotes
                    for quote in quotes:
                        if quote.get('symbol') == symbol:
                            classifications.append({'symbol':symbol,'quoteType':quote.get('quoteType'), 'name':quote.get('shortname',''), 'source':'Yahoo Finance search'})
                except Exception as exc:
                    print('Classification unavailable:',symbol,type(exc).__name__)
            for symbol in ('PG', 'AAPL'):
                frame = yf.Ticker(symbol, session=session).get_earnings_dates(limit=100)
                if frame is None:
                    continue
                for timestamp in frame.index:
                    t = timestamp.tz_convert('America/New_York')
                    timings.append({'symbol': symbol, 'reported_date': t.date().isoformat(),
                                    'timestamp_et': t.isoformat(),
                                    'timing': 'BMO' if t.hour < 9 or (t.hour == 9 and t.minute < 30) else 'AMC' if t.hour >= 16 else 'INTRADAY',
                                    'source': f'https://finance.yahoo.com/calendar/earnings?symbol={symbol}'})
    (OUT / 'timing_evidence.json').write_text(json.dumps(timings, indent=2))
    (OUT / 'supplementary_asset_classes.json').write_text(json.dumps(classifications, indent=2))
    print('Saved read-only price snapshot and timing evidence to', OUT)


if __name__ == '__main__':
    main()
