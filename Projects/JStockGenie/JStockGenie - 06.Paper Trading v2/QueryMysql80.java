import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.sql.*;

/** Read-only screener query. MYSQL80_URL is supplied through the environment. */
class QueryMysql80 {
    public static void main(String[] args) {
        try {
            String raw = System.getenv("MYSQL80_URL");
            if (raw == null || raw.isBlank()) throw new IllegalArgumentException();
            URI uri = URI.create(raw);
            if (!"mysql".equals(uri.getScheme())) throw new IllegalArgumentException();
            String[] credentials = uri.getRawUserInfo().split(":", 2);
            String db = uri.getPath();
            if (db == null || db.equals("/") || db.isEmpty()) db = "/jstocksnp";
            String jdbc = "jdbc:mysql://" + uri.getHost() + ":" + (uri.getPort() < 0 ? 3306 : uri.getPort()) + db;
            java.util.Properties properties = new java.util.Properties();
            properties.setProperty("user", URLDecoder.decode(credentials[0], StandardCharsets.UTF_8));
            properties.setProperty("password", URLDecoder.decode(credentials[1], StandardCharsets.UTF_8));
            properties.setProperty("connectTimeout", "10000");
            properties.setProperty("socketTimeout", "30000");
            try (Connection connection = DriverManager.getConnection(jdbc, properties)) {
                connection.setReadOnly(true);
                try (Statement statement = connection.createStatement()) {
                    statement.setQueryTimeout(30);
                    try (ResultSet result = statement.executeQuery("SELECT VERSION() AS server_version, DATABASE() AS database_name, CURRENT_DATE() AS database_date")) { print(result); }
                    try (ResultSet result = statement.executeQuery("SELECT scrip, close_price, assetclass, spread_type, exp_date, dte, short_strike, long_strike, breakeven, max_profit, max_loss, collateral, ror_pct, pop_pct FROM jstockview_credit_spread_screener WHERE dte <= 10 AND collateral <= 500 AND ror_pct >= 5")) { print(result); }
                }
            }
        } catch (SQLException e) {
            System.err.println("Database error: SQLState=" + e.getSQLState() + ", code=" + e.getErrorCode());
            for (Throwable cause = e.getCause(); cause != null; cause = cause.getCause()) {
                System.err.println("Cause: " + cause.getClass().getSimpleName());
            }
            System.exit(1);
        } catch (Exception e) {
            System.err.println("Connection configuration error: " + e.getClass().getSimpleName());
            System.exit(1);
        }
    }
    static void print(ResultSet result) throws SQLException {
        int n = result.getMetaData().getColumnCount();
        for (int i = 1; i <= n; i++) System.out.print((i > 1 ? "\t" : "") + result.getMetaData().getColumnLabel(i));
        System.out.println();
        int count = 0;
        while (result.next()) {
            for (int i = 1; i <= n; i++) System.out.print((i > 1 ? "\t" : "") + result.getString(i));
            System.out.println();
            count++;
        }
        System.out.println("Rows: " + count);
    }
}
