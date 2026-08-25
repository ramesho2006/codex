import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public class Mysql57To80Migrator {
    private static final String SOURCE_HOST = "209.209.40.79";
    private static final String SOURCE_PORT = "19824";
    private static String sourceDb = "jstocksnp";
    private static final String SOURCE_USER = "admin";
    private static final String SOURCE_PASS = "wQ7FbqmI";

    private static final String TARGET_HOST = "69.30.235.142";
    private static final String TARGET_PORT = "10020";
    private static String targetDb = "jstocksnp";
    private static final String TARGET_USER = "admin";
    private static final String TARGET_PASS = "mYVWXswF";

    private static final int BATCH_SIZE = 2000;
    private static final int PROGRESS_EVERY_ROWS = 100000;
    private static final boolean REPLACE_TARGET_DATABASE = true;

    public static void main(String[] args) throws Exception {
        Class.forName("com.mysql.jdbc.Driver");
        boolean resumeObjectsOnly = false;
        for (String arg : args) {
            if ("--resume-objects".equalsIgnoreCase(arg)) {
                resumeObjectsOnly = true;
            } else if (arg.startsWith("--db=")) {
                sourceDb = arg.substring("--db=".length());
                targetDb = sourceDb;
            } else if (arg.startsWith("--source-db=")) {
                sourceDb = arg.substring("--source-db=".length());
            } else if (arg.startsWith("--target-db=")) {
                targetDb = arg.substring("--target-db=".length());
            }
        }

        if (!resumeObjectsOnly) {
            try (Connection source = connect(SOURCE_HOST, SOURCE_PORT, sourceDb, SOURCE_USER, SOURCE_PASS);
                 Connection targetServer = connect(TARGET_HOST, TARGET_PORT, "", TARGET_USER, TARGET_PASS)) {

                prepareTargetDatabase(targetServer);
            }
        } else {
            System.out.println("Resume mode: keeping existing target database and creating views/routines/triggers/events only.");
        }

        try (Connection source = connect(SOURCE_HOST, SOURCE_PORT, sourceDb, SOURCE_USER, SOURCE_PASS);
             Connection target = connect(TARGET_HOST, TARGET_PORT, targetDb, TARGET_USER, TARGET_PASS)) {

            configureSession(source);
            configureSession(target);

            List<String> tables = names(source, "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA=? AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME");
            List<String> views = names(source, "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA=? AND TABLE_TYPE='VIEW' ORDER BY TABLE_NAME");
            List<String> procedures = names(source, "SELECT ROUTINE_NAME FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA=? AND ROUTINE_TYPE='PROCEDURE' ORDER BY ROUTINE_NAME");
            List<String> functions = names(source, "SELECT ROUTINE_NAME FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA=? AND ROUTINE_TYPE='FUNCTION' ORDER BY ROUTINE_NAME");
            List<String> triggers = names(source, "SELECT TRIGGER_NAME FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA=? ORDER BY ACTION_ORDER, TRIGGER_NAME");
            List<String> events = names(source, "SELECT EVENT_NAME FROM information_schema.EVENTS WHERE EVENT_SCHEMA=? ORDER BY EVENT_NAME");

            System.out.println("Database: " + sourceDb + " -> " + targetDb);
            System.out.println("Objects: tables=" + tables.size()
                    + ", views=" + views.size()
                    + ", procedures=" + procedures.size()
                    + ", functions=" + functions.size()
                    + ", triggers=" + triggers.size()
                    + ", events=" + events.size());

            if (!resumeObjectsOnly) {
                execute(target, "SET FOREIGN_KEY_CHECKS=0");
                execute(target, "SET UNIQUE_CHECKS=0");
                target.setAutoCommit(false);

                for (String table : tables) {
                    String ddl = showCreate(source, "TABLE", table, "Create Table");
                    execute(target, ddl);
                    System.out.println("Created table " + table);
                }

                for (String table : tables) {
                    long rows = copyTable(source, target, table);
                    System.out.println("Copied " + table + ": " + rows + " rows");
                }

                target.setAutoCommit(true);
            }

            dropExistingObjects(target, "VIEW", views);

            for (String function : functions) {
                dropExistingObject(target, "FUNCTION", function);
                String ddl = sanitizeDefiner(showCreate(source, "FUNCTION", function, "Create Function"));
                execute(target, ddl);
                System.out.println("Created function " + function);
            }

            for (String procedure : procedures) {
                dropExistingObject(target, "PROCEDURE", procedure);
                String ddl = sanitizeDefiner(showCreate(source, "PROCEDURE", procedure, "Create Procedure"));
                execute(target, ddl);
                System.out.println("Created procedure " + procedure);
            }

            createViewsInDependencyPasses(source, target, views);

            for (String trigger : triggers) {
                dropExistingObject(target, "TRIGGER", trigger);
                String ddl = sanitizeDefiner(showCreate(source, "TRIGGER", trigger, "SQL Original Statement"));
                execute(target, ddl);
                System.out.println("Created trigger " + trigger);
            }

            for (String event : events) {
                dropExistingObject(target, "EVENT", event);
                String ddl = sanitizeDefiner(showCreate(source, "EVENT", event, "Create Event"));
                execute(target, ddl);
                System.out.println("Created event " + event);
            }

            if (!resumeObjectsOnly) {
                execute(target, "SET UNIQUE_CHECKS=1");
                execute(target, "SET FOREIGN_KEY_CHECKS=1");

                validate(source, target, tables);
            } else {
                validateObjects(source, target);
            }
        }
    }

    private static Connection connect(String host, String port, String db, String user, String pass) throws SQLException {
        String schema = db == null || db.isEmpty() ? "" : "/" + db;
        String url = "jdbc:mysql://" + host + ":" + port + schema
                + "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC&characterEncoding=UTF-8"
                + "&useInformationSchema=true&zeroDateTimeBehavior=convertToNull&rewriteBatchedStatements=true&useServerPrepStmts=false";
        return DriverManager.getConnection(url, user, pass);
    }

    private static void prepareTargetDatabase(Connection targetServer) throws SQLException {
        configureSession(targetServer);
        boolean exists;
        try (PreparedStatement ps = targetServer.prepareStatement("SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME=?")) {
            ps.setString(1, targetDb);
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                exists = rs.getInt(1) > 0;
            }
        }
        if (exists) {
            if (!REPLACE_TARGET_DATABASE) {
            throw new SQLException("Target database already exists: " + targetDb + ". Aborting to avoid overwriting data.");
            }
            execute(targetServer, "DROP DATABASE `" + targetDb + "`");
            System.out.println("Dropped existing target database " + targetDb);
        }
        execute(targetServer, "CREATE DATABASE `" + targetDb + "` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
        System.out.println("Created target database " + targetDb);
    }

    private static void configureSession(Connection connection) throws SQLException {
        execute(connection, "SET SESSION sql_mode=''");
        execute(connection, "SET SESSION time_zone='+00:00'");
    }

    private static List<String> names(Connection source, String sql) throws SQLException {
        List<String> result = new ArrayList<>();
        try (PreparedStatement ps = source.prepareStatement(sql)) {
            ps.setString(1, sourceDb);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    result.add(rs.getString(1));
                }
            }
        }
        return result;
    }

    private static String showCreate(Connection source, String type, String objectName, String ddlColumn) throws SQLException {
        String sql = "SHOW CREATE " + type + " `" + sourceDb + "`.`" + objectName.replace("`", "``") + "`";
        try (Statement st = source.createStatement();
             ResultSet rs = st.executeQuery(sql)) {
            if (!rs.next()) {
                throw new SQLException("SHOW CREATE returned no rows for " + type + " " + objectName);
            }
            ResultSetMetaData md = rs.getMetaData();
            for (int i = 1; i <= md.getColumnCount(); i++) {
                if (ddlColumn.equalsIgnoreCase(md.getColumnLabel(i))) {
                    return rs.getString(i);
                }
            }
            return rs.getString(md.getColumnCount());
        }
    }

    private static String sanitizeDefiner(String ddl) {
        return ddl
                .replaceAll("(?i)DEFINER=`[^`]+`@`[^`]+`\\s+", "")
                .replaceAll("(?i)DEFINER=[^\\s]+\\s+", "");
    }

    private static void createViewsInDependencyPasses(Connection source, Connection target, List<String> views) throws SQLException {
        Map<String, String> pending = new LinkedHashMap<>();
        for (String view : views) {
            pending.put(view, sanitizeDefiner(showCreate(source, "VIEW", view, "Create View")));
        }

        SQLException lastError = null;
        while (!pending.isEmpty()) {
            boolean createdAny = false;
            List<String> created = new ArrayList<>();
            for (Map.Entry<String, String> entry : pending.entrySet()) {
                try {
                    execute(target, entry.getValue());
                    System.out.println("Created view " + entry.getKey());
                    created.add(entry.getKey());
                    createdAny = true;
                } catch (SQLException e) {
                    lastError = e;
                }
            }
            for (String view : created) {
                pending.remove(view);
            }
            if (!createdAny) {
                throw new SQLException("Could not resolve view dependencies. Remaining views: " + pending.keySet(), lastError);
            }
        }
    }

    private static void dropExistingObjects(Connection target, String type, List<String> names) throws SQLException {
        for (String name : names) {
            dropExistingObject(target, type, name);
        }
    }

    private static void dropExistingObject(Connection target, String type, String name) throws SQLException {
        execute(target, "DROP " + type + " IF EXISTS `" + name.replace("`", "``") + "`");
    }

    private static long copyTable(Connection source, Connection target, String table) throws SQLException {
        String qTable = "`" + table.replace("`", "``") + "`";
        try (Statement select = source.createStatement(ResultSet.TYPE_FORWARD_ONLY, ResultSet.CONCUR_READ_ONLY)) {
            select.setFetchSize(Integer.MIN_VALUE);
            try (ResultSet rs = select.executeQuery("SELECT * FROM `" + sourceDb + "`." + qTable)) {
                ResultSetMetaData md = rs.getMetaData();
                int cols = md.getColumnCount();
                StringBuilder insert = new StringBuilder("INSERT INTO ").append(qTable).append(" (");
                StringBuilder values = new StringBuilder(" VALUES (");
                for (int i = 1; i <= cols; i++) {
                    if (i > 1) {
                        insert.append(',');
                        values.append(',');
                    }
                    insert.append('`').append(md.getColumnName(i).replace("`", "``")).append('`');
                    values.append('?');
                }
                insert.append(')').append(values).append(')');

                long count = 0;
                try (PreparedStatement ps = target.prepareStatement(insert.toString())) {
                    while (rs.next()) {
                        for (int i = 1; i <= cols; i++) {
                            setValue(ps, i, rs, md.getColumnType(i));
                        }
                        ps.addBatch();
                        count++;
                        if (count % BATCH_SIZE == 0) {
                            ps.executeBatch();
                            target.commit();
                        }
                        if (count % PROGRESS_EVERY_ROWS == 0) {
                            System.out.println("  " + table + ": " + count + " rows...");
                        }
                    }
                    ps.executeBatch();
                    target.commit();
                } catch (SQLException e) {
                    target.rollback();
                    throw e;
                }
                return count;
            }
        }
    }

    private static void setValue(PreparedStatement ps, int index, ResultSet rs, int type) throws SQLException {
        Object value = rs.getObject(index);
        if (value == null) {
            ps.setNull(index, type);
            return;
        }
        switch (type) {
            case Types.BINARY:
            case Types.VARBINARY:
            case Types.LONGVARBINARY:
            case Types.BLOB:
                ps.setBytes(index, rs.getBytes(index));
                break;
            default:
                ps.setObject(index, value);
        }
    }

    private static void validate(Connection source, Connection target, List<String> tables) throws SQLException {
        int mismatches = 0;
        for (String table : tables) {
            long sourceCount = count(source, sourceDb, table);
            long targetCount = count(target, targetDb, table);
            if (sourceCount != targetCount) {
                mismatches++;
                System.out.println("MISMATCH " + table + ": source=" + sourceCount + ", target=" + targetCount);
            }
        }
        if (mismatches > 0) {
            throw new SQLException("Validation failed. Row-count mismatches: " + mismatches);
        }
        System.out.println("Validation passed. Row counts match for " + tables.size() + " tables.");
    }

    private static void validateObjects(Connection source, Connection target) throws SQLException {
        long sourceTables = objectCount(source, "information_schema.TABLES", "TABLE_SCHEMA", sourceDb, null);
        long targetTables = objectCount(target, "information_schema.TABLES", "TABLE_SCHEMA", targetDb, null);
        long sourceRoutines = objectCount(source, "information_schema.ROUTINES", "ROUTINE_SCHEMA", sourceDb, null);
        long targetRoutines = objectCount(target, "information_schema.ROUTINES", "ROUTINE_SCHEMA", targetDb, null);
        long sourceViews = objectCount(source, "information_schema.TABLES", "TABLE_SCHEMA", sourceDb, "TABLE_TYPE='VIEW'");
        long targetViews = objectCount(target, "information_schema.TABLES", "TABLE_SCHEMA", targetDb, "TABLE_TYPE='VIEW'");
        System.out.println("Object validation: source tables/views=" + sourceTables + ", target tables/views=" + targetTables
                + ", source views=" + sourceViews + ", target views=" + targetViews
                + ", source routines=" + sourceRoutines + ", target routines=" + targetRoutines);
    }

    private static long objectCount(Connection connection, String table, String schemaColumn, String schema, String extraWhere) throws SQLException {
        String sql = "SELECT COUNT(*) FROM " + table + " WHERE " + schemaColumn + "=?";
        if (extraWhere != null && !extraWhere.isEmpty()) {
            sql += " AND " + extraWhere;
        }
        try (PreparedStatement ps = connection.prepareStatement(sql)) {
            ps.setString(1, schema);
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                return rs.getLong(1);
            }
        }
    }

    private static long count(Connection connection, String schema, String table) throws SQLException {
        try (Statement st = connection.createStatement();
             ResultSet rs = st.executeQuery("SELECT COUNT(*) FROM `" + schema + "`.`" + table.replace("`", "``") + "`")) {
            rs.next();
            return rs.getLong(1);
        }
    }

    private static void execute(Connection connection, String sql) throws SQLException {
        try (Statement st = connection.createStatement()) {
            st.execute(sql);
        }
    }
}
