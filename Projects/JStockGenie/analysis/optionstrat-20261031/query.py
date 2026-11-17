import os,json,pymysql,sys
from urllib.parse import urlparse,unquote
u=urlparse(os.environ['MYSQL80_URL']); c=pymysql.connect(host=u.hostname,port=u.port or 3306,user=unquote(u.username),password=unquote(u.password),database=u.path.strip('/'),cursorclass=pymysql.cursors.DictCursor)
with c.cursor() as q:
 q.execute('SET SESSION TRANSACTION READ ONLY')
 q.execute(sys.stdin.read()); print(json.dumps(q.fetchall(),default=str))
c.close()
