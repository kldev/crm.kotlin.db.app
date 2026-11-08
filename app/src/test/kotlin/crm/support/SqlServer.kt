package crm.support

import org.testcontainers.containers.GenericContainer
import org.testcontainers.containers.wait.strategy.Wait
import java.nio.file.Files
import java.nio.file.Path
import java.sql.Connection
import java.sql.DriverManager
import java.time.Duration

/**
 * One SQL Server 2025 Express container for the whole test run - the same image and edition as docker compose.
 * Bootstrapped with infrastructure/sql/init.sql (as sa, like the db-init container); Flyway then runs at Spring
 * context start with the migrator login, and the application connects with the app login (EXECUTE on `app` only).
 */
object SqlServer {
    const val DB = "crm"
    const val SA_PASSWORD = "Test_Sa_Passw0rd#1"
    const val MIGRATOR = "crm_migrator"
    const val MIGRATOR_PASSWORD = "Test_Migr_Passw0rd#1"
    const val APP = "crm_app"
    const val APP_PASSWORD = "Test_App_Passw0rd#1"

    private val container: GenericContainer<*> by lazy {
        GenericContainer("mcr.microsoft.com/mssql/server:2025-latest")
            .withEnv("ACCEPT_EULA", "Y")
            .withEnv("MSSQL_PID", "Express")
            .withEnv("MSSQL_SA_PASSWORD", SA_PASSWORD)
            .withExposedPorts(1433)
            .waitingFor(
                Wait.forLogMessage(".*SQL Server is now ready for client connections.*", 1)
                    .withStartupTimeout(Duration.ofMinutes(3)),
            )
            .also {
                it.start()
                bootstrap(it)
            }
    }

    val url: String
        get() = "jdbc:sqlserver://${container.host}:${container.getMappedPort(1433)};databaseName=$DB;" +
            "encrypt=true;trustServerCertificate=true"

    private fun masterUrl(c: GenericContainer<*>) =
        "jdbc:sqlserver://${c.host}:${c.getMappedPort(1433)};encrypt=true;trustServerCertificate=true"

    fun connect(user: String, password: String): Connection = DriverManager.getConnection(url, user, password)

    fun migrator(): Connection = connect(MIGRATOR, MIGRATOR_PASSWORD)

    fun app(): Connection = connect(APP, APP_PASSWORD)

    /** Runs init.sql the way sqlcmd does: $(VAR) substitution, batches split on GO. */
    private fun bootstrap(c: GenericContainer<*>) {
        val vars = mapOf(
            "DB_NAME" to DB,
            "MIGRATOR_LOGIN" to MIGRATOR,
            "MIGRATOR_PASSWORD" to MIGRATOR_PASSWORD,
            "APP_LOGIN" to APP,
            "APP_PASSWORD" to APP_PASSWORD,
        )
        var script = Files.readString(Path.of("../infrastructure/sql/init.sql"))
        vars.forEach { (k, v) -> script = script.replace("$($k)", v) }
        val batches = script.split(Regex("(?im)^\\s*GO\\s*$")).map { it.trim() }.filter { it.isNotEmpty() }

        // The log line appears slightly before logins are accepted.
        var connection: Connection? = null
        repeat(30) {
            if (connection == null) {
                connection = runCatching { DriverManager.getConnection(masterUrl(c), "sa", SA_PASSWORD) }.getOrNull()
                if (connection == null) Thread.sleep(1000)
            }
        }
        checkNotNull(connection) { "SQL Server did not accept connections" }.use { conn ->
            conn.createStatement().use { st -> batches.forEach { st.execute(it) } }
        }
    }
}
