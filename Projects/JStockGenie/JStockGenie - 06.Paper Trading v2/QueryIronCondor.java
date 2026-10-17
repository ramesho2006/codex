import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.sql.*;
import java.util.Properties;

class QueryIronCondor {
  public static void main(String[] args) throws Exception {
    String raw = System.getenv("MYSQL80_URL");
    if (raw == null || raw.isBlank()) throw new IllegalArgumentException("MYSQL80_URL missing");
    URI u = URI.create(raw); String[] ui = u.getRawUserInfo().split(":", 2);
    String db = u.getPath(); if (db == null || db.equals("/")) db = "/jstocksnp";
    String jdbc = "jdbc:mysql://" + u.getHost() + ":" + (u.getPort() < 0 ? 3306 : u.getPort()) + db;
    Properties p = new Properties(); p.setProperty("user", URLDecoder.decode(ui[0], StandardCharsets.UTF_8)); p.setProperty("password", URLDecoder.decode(ui[1], StandardCharsets.UTF_8)); p.setProperty("connectTimeout", "10000"); p.setProperty("socketTimeout", "30000");
    String q = "select scrip, close_price, exp_date, dte, short_put_strike, long_put_strike, short_call_strike, long_call_strike, lower_breakeven, upper_breakeven, max_profit, max_loss, collateral, ror_pct, pop_pct from jstockview_iron_condor_screener where dte <= 10 and collateral <= 500";
    try (Connection c = DriverManager.getConnection(jdbc,p); Statement s = c.createStatement()) { s.setQueryTimeout(30); try (ResultSet r = s.executeQuery(q)) { int n=r.getMetaData().getColumnCount(); for(int i=1;i<=n;i++) System.out.print((i>1?"\t":"")+r.getMetaData().getColumnLabel(i)); System.out.println(); int count=0; while(r.next()){ for(int i=1;i<=n;i++) System.out.print((i>1?"\t":"")+r.getString(i)); System.out.println(); count++; } System.out.println("Rows: "+count); } }
  }
}
