import java.sql.*;

public class TempCheckGreyEma {
    public static void main(String[] args) throws Exception {
        Class.forName("com.mysql.cj.jdbc.Driver");
        for (String schema : new String[]{"jstocksnp", "jstocknse"}) {
        String url = "jdbc:mysql://69.30.235.142:10020/" + schema + "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=America%2FChicago";
        try (Connection c = DriverManager.getConnection(url, "admin", "mYVWXswF"); Statement s = c.createStatement()) {
            String[] sqls = {
                "SELECT SCRIP, TRIM(REPLACE(FREQUENCY,CHAR(13),'')) FREQ, COUNT(*) CNT, MIN(DATE) MIN_DATE, MAX(DATE) MAX_DATE FROM jstockdata_hatrend_extend WHERE SCRIP LIKE '%CFLU%' GROUP BY SCRIP,FREQ ORDER BY FREQ",
                "SELECT SCRIP, FREQUENCY, DATE, CLOSE, EMA5, EMA12, EMA34, EMA50, EMA72, EMA89 FROM jstockdata_hatrend_extend WHERE SCRIP LIKE '%CFLU%' AND FREQUENCY LIKE 'MONTHLY%' ORDER BY DATE DESC LIMIT 3",
                "SELECT SCRIP, ASSET_CLASS, MONTHLY_FAST_SCORE, MONTHLY_MEDIUM_SCORE, MONTHLY_SLOW_SCORE, MONTHLY_TOTAL_SCORE FROM jstockview_ema_score_board WHERE SCRIP LIKE '%CFLU%'"
            };
            for (String sql : sqls) {
                try (ResultSet rs = s.executeQuery(sql)) {
                    ResultSetMetaData md = rs.getMetaData();
                    while (rs.next()) {
                        for (int i=1; i<=md.getColumnCount(); i++) System.out.print((i==1?"":"|") + md.getColumnLabel(i) + "=" + rs.getString(i));
                        System.out.println();
                    }
                }
            }
        }
        }
    }
}
