"""Append concise weekly recommendation JSON. Validate before --apply; never overwrite history."""
import argparse,json,os
from pathlib import Path
from decimal import Decimal as D
from datetime import date
from urllib.parse import urlparse,unquote
import pymysql
TABLE='jstockdata_reco_weekly_optionstrat'
COLS='review_date scrip strategy expiry_date dte short_strike long_strike delta_short_leg delta_long_leg contract_quantity daily_trend weekly_trend underlying_close ha_rsi remark roi_pct breakeven pop_pct collateral roi_basis earnings_date earnings_in_holding_period legs_json qualifications'.split()
KEYS='review_date scrip strategy expiry_date short_strike long_strike contract_quantity'.split()
NUM=set('dte short_strike long_strike delta_short_leg delta_long_leg contract_quantity underlying_close ha_rsi roi_pct breakeven pop_pct collateral earnings_in_holding_period'.split())
def canonical(k,v):
 if v is None:return None
 if k=='legs_json':return json.dumps(json.loads(v) if isinstance(v,str) else v,sort_keys=True)
 if k in NUM:return D(str(int(v) if isinstance(v,bool) else v))
 return str(v)
def validate(r):
 if set(r)-set(COLS)-{'reco_id'} or set(COLS)-set(r):raise ValueError('Snapshot does not match concise schema')
 if int(r['dte'])!=(date.fromisoformat(r['expiry_date'])-date.fromisoformat(r['review_date'])).days:raise ValueError('DTE mismatch')
 if not D('.4')<=D(r['delta_short_leg'])<=D('.5'):raise ValueError('Short delta outside requested band')
 if not 0<=D(r['pop_pct'])<=100:raise ValueError('Invalid probability')
 qty=int(r['contract_quantity']);legs=r['legs_json'];sell=[x for x in legs if x['side']=='SELL'];buy=[x for x in legs if x['side']=='BUY']
 if qty<=0 or len(sell)!=1:raise ValueError('Invalid position size/legs')
 csp=r['strategy']=='CASH_SECURED_PUT'
 if r['strategy'] not in ['CASH_SECURED_PUT','BULL_PUT_CREDIT_SPREAD','BEAR_CALL_CREDIT_SPREAD']:raise ValueError('Unknown strategy')
 if (csp and (buy or r['long_strike'] is not None or r['delta_long_leg'] is not None)) or (not csp and len(buy)!=1):raise ValueError('Invalid hedge')
 if not csp and not D('.2')<=D(r['delta_long_leg'])<=D('.3'):raise ValueError('Long delta outside requested band')
 short=D(r['short_strike']);long=None if csp else D(r['long_strike']);typ='C' if r['strategy']=='BEAR_CALL_CREDIT_SPREAD' else 'P'
 if (r['strategy']=='BEAR_CALL_CREDIT_SPREAD' and (typ!='C' or long<=short)) or (r['strategy']!='BEAR_CALL_CREDIT_SPREAD' and (typ!='P' or (not csp and long>=short))):raise ValueError('Strike/type mismatch')
 multiplier=int(sell[0]['multiplier']);scale=D(multiplier*qty)
 if multiplier<=0:raise ValueError('Invalid multiplier')
 for leg in legs:
  expected=short if leg['side']=='SELL' else long
  delta=r['delta_short_leg'] if leg['side']=='SELL' else r['delta_long_leg']
  if D(leg['strike'])!=expected or D(leg['delta_abs'])!=D(delta) or leg['expiry_date']!=r['expiry_date'] or leg['option_type']!=typ or int(leg['quantity'])!=qty or int(leg['multiplier'])!=multiplier:raise ValueError('Leg detail mismatch')
 capital=(short if csp else abs(short-long))*scale
 if D(r['collateral'])!=capital:raise ValueError('Collateral mismatch')
 credit=((short-D(r['breakeven'])) if typ=='P' else (D(r['breakeven'])-short))*scale
 if not 0<credit<capital:raise ValueError('Invalid breakeven/payoff')
 basis='FULL_CASH_COLLATERAL' if csp else 'MAXIMUM_LOSS'
 if r['roi_basis']!=basis or abs(credit/(capital if csp else capital-credit)*100-D(r['roi_pct']))>D('.011'):raise ValueError('ROI/breakeven mismatch')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('snapshot');ap.add_argument('--apply',action='store_true');a=ap.parse_args()
 rows=json.loads(Path(a.snapshot).read_text(encoding='utf-8-sig'))
 for r in rows:validate(r)
 print('Validated',len(rows),'concise recommendations')
 if not a.apply:return
 u=urlparse(os.environ['MYSQL80_URL']);assert u.scheme=='mysql' and u.path.strip('/')=='jstocksnp'
 c=pymysql.connect(host=u.hostname,port=u.port or 3306,user=unquote(u.username),password=unquote(u.password),database='jstocksnp',cursorclass=pymysql.cursors.DictCursor,autocommit=False)
 locked=False
 try:
  with c.cursor() as q:
   q.execute("SELECT GET_LOCK('jstocksnp.options_reco_import',10) AS acquired");locked=q.fetchone()['acquired']==1
   if not locked:raise RuntimeError('Another recommendation import is active')
   q.execute(Path(__file__).with_name('schema.sql').read_text(encoding='utf-8-sig'))
   q.execute('SHOW COLUMNS FROM '+TABLE);assert [x['Field'] for x in q.fetchall()]==['reco_id']+COLS,'Unexpected table schema'
  c.begin();inserted=skipped=0
  with c.cursor() as q:
   for r in rows:
    q.execute('SELECT * FROM '+TABLE+' WHERE '+' AND '.join('`'+k+'` <=> %s' for k in KEYS),[r[k] for k in KEYS]);existing=q.fetchall()
    if existing:
     if any(all(canonical(k,e[k])==canonical(k,r[k]) for k in COLS) for e in existing):skipped+=1;continue
     raise ValueError('Same-date recommendation differs. No overwrite performed; use a separately reviewed date or explicitly resolve the revision.')
    q.execute('INSERT INTO '+TABLE+' ('+','.join('`'+k+'`' for k in COLS)+') VALUES ('+','.join(['%s']*len(COLS))+')',[json.dumps(r[k]) if k=='legs_json' else r[k] for k in COLS]);inserted+=1
  c.commit();print('Inserted',inserted,'; identical rows skipped',skipped)
 except Exception:c.rollback();raise
 finally:
  if locked:
   with c.cursor() as q:q.execute("SELECT RELEASE_LOCK('jstocksnp.options_reco_import')")
  c.close()
if __name__=='__main__':main()
