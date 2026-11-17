"""Append validated recommendation snapshots. No updates/deletes; retries skip identical rows."""
import argparse,hashlib,json,os
from pathlib import Path
from decimal import Decimal
from datetime import date
from urllib.parse import urlparse,unquote
import pymysql
TABLE='jstockdata_option_recommendations'
def digest(value):
 return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
def validate(r):
 d=lambda k: Decimal(str(r[k]))
 assert r['dte']==(date.fromisoformat(r['expiry_date'])-date.fromisoformat(r['reviewed_date'])).days
 assert Decimal('.4')<=d('short_delta_abs')<=Decimal('.5')
 assert r['long_delta_abs'] is None or Decimal('.2')<=d('long_delta_abs')<=Decimal('.3')
 assert d('midpoint_pop_pct')+d('midpoint_pol_approx_pct')==100
 scale=d('contract_quantity')*d('contract_multiplier')
 csp=r['strategy']=='CASH_SECURED_PUT'
 capital=d('short_strike')*scale if csp else abs(d('short_strike')-d('long_strike'))*scale
 for prefix in ['midpoint','quoted_side']:
  credit=d(prefix+'_credit_usd'); loss=d(prefix+'_max_loss_usd')
  assert credit>0 and loss>0 and credit+loss==capital
  roi=credit/(capital if csp else loss)*100
  assert abs(roi-d(prefix+'_roi_pct'))<Decimal('.011')
  be=d('short_strike')+(credit/scale if r['option_type']=='C' else -credit/scale)
  assert abs(be-d(prefix+'_breakeven'))<Decimal('.011')
 if csp: assert d('csp_cash_collateral_usd')==capital
 legs=r['legs_json']; short=next(x for x in legs if x['side']=='SELL')
 long=next((x for x in legs if x['side']=='BUY'),None)
 assert (Decimal(short['bid'])-(Decimal(long['ask']) if long else 0))*scale==d('quoted_side_credit_usd')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('snapshot');ap.add_argument('--apply',action='store_true');a=ap.parse_args()
 rows=json.loads(Path(a.snapshot).read_text(encoding='utf-8-sig'))
 for r in rows: validate(r)
 print(f'Validated {len(rows)} recommendation snapshots')
 if not a.apply: return
 u=urlparse(os.environ['MYSQL80_URL'])
 assert u.scheme=='mysql' and u.path.strip('/')=='jstocksnp','Unexpected database configuration'
 c=pymysql.connect(host=u.hostname,port=u.port or 3306,user=unquote(u.username),password=unquote(u.password),database='jstocksnp',charset='utf8mb4',autocommit=False)
 try:
  with c.cursor() as q:
   q.execute('SELECT VERSION(), DATABASE()'); v,db=q.fetchone(); assert v.startswith('8.') and db=='jstocksnp'
   q.execute(Path(__file__).with_name('schema.sql').read_text(encoding='utf-8-sig'))
  c.begin(); inserted=skipped=0
  with c.cursor() as q:
   for source in rows:
    r=dict(source)
    key=digest([r[k] for k in ['review_key','scrip','strategy','expiry_date','short_strike','long_strike']])
    payload=digest(r)
    q.execute(f'SELECT payload_sha256 FROM {TABLE} WHERE snapshot_key=%s',(key,)); old=q.fetchone()
    if old:
     if old[0]!=payload: raise ValueError('Existing snapshot differs; preserve history using a new review_key/revision')
     skipped+=1;continue
    r.update(snapshot_key=key,payload_sha256=payload)
    for k in ['legs_json','assumptions_json']: r[k]=json.dumps(r[k],ensure_ascii=False)
    cols=list(r)
    q.execute(f"INSERT INTO {TABLE} ("+','.join('`'+k+'`' for k in cols)+') VALUES ('+','.join(['%s']*len(cols))+')',[r[k] for k in cols]); inserted+=1
  c.commit()
  with c.cursor() as q:
   q.execute(f'SELECT reviewed_date,strategy,COUNT(*) FROM {TABLE} WHERE review_key=%s GROUP BY reviewed_date,strategy',(rows[0]['review_key'],))
   print(json.dumps(q.fetchall(),default=str))
  print(f'Inserted {inserted}; identical existing snapshots skipped {skipped}')
 except Exception:
  c.rollback();raise
 finally:c.close()
if __name__=='__main__':main()
