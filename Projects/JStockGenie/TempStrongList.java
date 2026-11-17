import java.sql.*;

public class TempStrongList {
  public static void main(String[] args) throws Exception {
    Class.forName("com.mysql.cj.jdbc.Driver");
    String q = """
      SELECT CASE WHEN e.DAILY_TOTAL_SCORE=3 THEN 'BULLISH' ELSE 'BEARISH' END AS SIDE,
             s.SCRIP, s.AssetClass, e.CLOSE
      FROM jstockview_ema_score_board e
      JOIN jstockview_smadelta_screener scr ON scr.SCRIP=e.SCRIP AND scr.FREQUENCY='DAILY'
      JOIN jstockdata_scrips s ON UPPER(TRIM(s.SCRIP))=UPPER(TRIM(e.SCRIP))
      WHERE ((e.DAILY_TOTAL_SCORE=3 AND e.WEEKLY_TOTAL_SCORE=3)
          OR (e.DAILY_TOTAL_SCORE=-3 AND e.WEEKLY_TOTAL_SCORE=-3))
        AND UPPER(TRIM(COALESCE(scr.SMADeltaTrend,''))) <> 'EXIT'
      ORDER BY SIDE, s.SCRIP
      """;
    try (Connection c=DriverManager.getConnection("jdbc:mysql://69.30.235.142:10020/jstocksnp","admin","mYVWXswF");
         Statement s=c.createStatement(); ResultSet r=s.executeQuery(q)) {
      while(r.next()) System.out.printf("%s|%s|%s|%s%n",r.getString(1),r.getString(2),r.getString(3),r.getString(4));
    }
  }
}
