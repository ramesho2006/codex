from pathlib import Path
import json,os,pymysql
from urllib.parse import urlparse,unquote
from datetime import datetime
p=Path('analysis/weekly-trend-options-review'); stamp=datetime.now().strftime('%Y%m%d_%H%M%S')
fields=[('recommendation_id','reco_id','BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY'),('reviewed_date','review_date','DATE NOT NULL'),('scrip','scrip','VARCHAR(24) NOT NULL'),('strategy','strategy','VARCHAR(32) NOT NULL'),('expiry_date','expiry_date','DATE NOT NULL'),('dte','dte','SMALLINT NOT NULL'),('option_type','option_type','CHAR(1) NOT NULL'),('short_strike','short_strike','DECIMAL(14,4) NOT NULL'),('long_strike','long_strike','DECIMAL(14,4) NULL'),('short_delta_abs','delta_short_leg','DECIMAL(7,4) NOT NULL'),('long_delta_abs','delta_long_leg','DECIMAL(7,4) NULL'),('contract_quantity','contract_quantity','INT NOT NULL'),('daily_trend','daily_trend','VARCHAR(8) NOT NULL'),('weekly_trend','weekly_trend','VARCHAR(8) NOT NULL'),('underlying_close','underlying_close','DECIMAL(14,4) NOT NULL'),('ha_rsi','ha_rsi','DECIMAL(8,4) NULL'),('recommendation_status','remark','VARCHAR(40) NOT NULL'),('midpoint_roi_pct','roi_pct',"DECIMAL(12,4) NOT NULL COMMENT 'Midpoint holding-period maximum ROI, not expected return'"),('midpoint_pop_pct','pop_pct',"DECIMAL(7,3) NOT NULL COMMENT 'OptionStrat modeled midpoint probability of profit'"),('Collateral','collateral',"DECIMAL(16,4) NOT NULL COMMENT 'USD gross collateral before premium; multiplier retained per leg in legs_json'"),('roi_basis','roi_basis','VARCHAR(24) NOT NULL'),('earnings_date','earnings_date','DATE NULL'),('earnings_in_holding_period','earnings_in_holding_period','BOOLEAN NOT NULL'),('legs_json','legs_json','JSON NOT NULL'),('qualifications','qualifications','TEXT NOT NULL')]
schema='CREATE TABLE IF NOT EXISTS jstockdata_option_recommendations (\n'+',\n'.join(' `'+new+'` '+typ for old,new,typ in fields)+''',
 KEY ix_reco_review (review_date,strategy),
 KEY ix_reco_symbol (scrip,review_date),
 KEY ix_reco_expiry (expiry_date),
 CHECK (dte=DATEDIFF(expiry_date,review_date)),
 CHECK (contract_quantity>0 AND collateral>0),
 CHECK (pop_pct BETWEEN 0 AND 100),
 CHECK (delta_short_leg BETWEEN 0 AND 1 AND (delta_long_leg IS NULL OR delta_long_leg BETWEEN 0 AND 1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Weekly recommendations; not executed trades';
'''
u=urlparse(os.environ['MYSQL80_URL']);assert u.path.strip('/')=='jstocksnp'
c=pymysql.connect(host=u.hostname,port=u.port or 3306,user=unquote(u.username),password=unquote(u.password),database='jstocksnp',cursorclass=pymysql.cursors.DictCursor)
t='jstockdata_option_recommendations'; backup=t+'_backup_'+stamp; staging=t+'_new_'+stamp
with c.cursor() as q:
 q.execute("SELECT TABLE_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE REFERENCED_TABLE_SCHEMA=DATABASE() AND REFERENCED_TABLE_NAME=%s",(t,)); assert not q.fetchall(),'Foreign key dependencies require explicit migration'
 q.execute("SELECT VIEW_NAME FROM information_schema.VIEW_TABLE_USAGE WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=%s",(t,)); assert not q.fetchall(),'View dependencies require migration'
 q.execute('SHOW CREATE TABLE '+t); ddl=q.fetchone()['Create Table']
 q.execute('SELECT * FROM '+t+' ORDER BY recommendation_id'); original=q.fetchall(); assert original
 out=p/('schema-backup-'+stamp);out.mkdir()
 (out/'original-schema.sql').write_text(ddl,encoding='utf-8');(out/'original-rows.json').write_text(json.dumps(original,default=str,indent=2),encoding='utf-8')
 q.execute(schema.replace('IF NOT EXISTS '+t,staging))
 target=','.join('`'+new+'`' for old,new,typ in fields); source=','.join('`'+old+'`' for old,new,typ in fields)
 q.execute('INSERT INTO '+staging+' ('+target+') SELECT '+source+' FROM '+t)
 q.execute('SELECT * FROM '+staging+' ORDER BY reco_id'); migrated=q.fetchall()
 expected=[{new:r[old] for old,new,typ in fields} for r in original]
 assert migrated==expected,'Migration data mismatch'
 c.commit()
 q.execute('RENAME TABLE '+t+' TO '+backup+', '+staging+' TO '+t)
 q.execute('SELECT * FROM '+t+' ORDER BY reco_id');assert q.fetchall()==expected
 (p/'schema.sql').write_text(schema,encoding='utf-8')
 for r in migrated:r['legs_json']=json.loads(r['legs_json']) if isinstance(r['legs_json'],str) else r['legs_json']
 (Path('analysis/optionstrat-20261031/recommendations_concise.json')).write_text(json.dumps(migrated,default=str,indent=2),encoding='utf-8')
 (out/'migration-result.json').write_text(json.dumps({'backup_table':backup,'rows':len(original),'columns':[f[1] for f in fields]},indent=2),encoding='utf-8')
 print(json.dumps({'backup_table':backup,'rows_preserved':len(original),'column_count':len(fields),'columns':[f[1] for f in fields]}))
c.close()
