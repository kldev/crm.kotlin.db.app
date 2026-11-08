package crm.support

import org.junit.jupiter.api.BeforeEach
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.server.LocalServerPort
import org.springframework.security.crypto.factory.PasswordEncoderFactories
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import java.sql.Types

/**
 * Base for tests on a real SQL Server and real HTTP. The database is migrated by Flyway (migrator login) at the
 * first context start and seeded once with a small data set through the same `seed.run` as production:
 * 1 ADMIN, 2 MANAGER, 6 SALES (teams of 3), 300 clients, 300 projects, 100 comments.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
abstract class IntegrationTest {
    @LocalServerPort
    protected var port: Int = 0

    @BeforeEach
    fun seedData() = ensureSeeded()

    protected fun client() = ApiClient("http://localhost:$port")

    /** A client logged in as [login]; fails the test when login does not succeed. */
    protected fun loggedIn(login: String, password: String = PERF_PASSWORD): ApiClient {
        val client = client()
        val response = client.login(login, password)
        check(response.status == 200) { "login $login failed: ${response.status} ${response.body}" }
        return client
    }

    /** Scalar from the database as the migrator (test assertions only - the application never does this). */
    protected fun <T> scalar(sql: String, vararg params: Any?): T? = SqlServer.migrator().use { c ->
        c.prepareStatement(sql).use { ps ->
            params.forEachIndexed { i, p -> ps.setObject(i + 1, p) }
            ps.executeQuery().use { rs ->
                @Suppress("UNCHECKED_CAST")
                if (rs.next()) rs.getObject(1) as T? else null
            }
        }
    }

    companion object {
        const val PERF_PASSWORD = "Perf-Test-Passw0rd"
        const val ADMIN_LOGIN = "admin"
        const val ADMIN_PASSWORD = "Admin-Test-Passw0rd"
        const val MAX_FAILED = 3

        @Volatile
        private var seeded = false

        @JvmStatic
        @DynamicPropertySource
        fun properties(registry: DynamicPropertyRegistry) {
            registry.add("spring.datasource.url") { SqlServer.url }
            registry.add("spring.datasource.username") { SqlServer.APP }
            registry.add("spring.datasource.password") { SqlServer.APP_PASSWORD }
            registry.add("spring.flyway.enabled") { "true" }
            registry.add("spring.flyway.url") { SqlServer.url }
            registry.add("spring.flyway.user") { SqlServer.MIGRATOR }
            registry.add("spring.flyway.password") { SqlServer.MIGRATOR_PASSWORD }
            registry.add("spring.flyway.placeholders.app_user") { SqlServer.APP }
            registry.add("crm.auth.admin-login") { ADMIN_LOGIN }
            registry.add("crm.auth.admin-password") { ADMIN_PASSWORD }
            registry.add("crm.auth.max-failed-logins") { MAX_FAILED }
            registry.add("crm.auth.lock-minutes") { 15 }
            registry.add("crm.storage.endpoint") { RustFs.endpoint }
            registry.add("crm.storage.access-key") { RustFs.ACCESS_KEY }
            registry.add("crm.storage.secret-key") { RustFs.SECRET_KEY }
            registry.add("crm.storage.bucket") { RustFs.BUCKET }
        }

        /** Seeds once per test run, after the Spring context (and so Flyway) has started. */
        @Synchronized
        fun ensureSeeded() {
            if (seeded) return
            val hash = PasswordEncoderFactories.createDelegatingPasswordEncoder().encode(PERF_PASSWORD)
            SqlServer.migrator().use { c ->
                c.prepareStatement(
                    "EXEC seed.run @clients = ?, @admins = ?, @managers = ?, @sales = ?, @password_hash = ?, " +
                        "@team_size = ?, @projects = ?, @comments = ?, @random_seed = ?, @batch_size = ?",
                ).use { ps ->
                    listOf(300, 1, 2, 6).forEachIndexed { i, v -> ps.setInt(i + 1, v) }
                    ps.setObject(5, hash, Types.VARCHAR)
                    listOf(3, 300, 100, 7, 1000).forEachIndexed { i, v -> ps.setInt(i + 6, v) }
                    ps.execute()
                }
                c.prepareStatement("EXEC seed.desk_run @password_hash = ?, @tickets = ?, @random_seed = ?").use { ps ->
                    ps.setObject(1, hash, Types.VARCHAR)
                    ps.setInt(2, 60)
                    ps.setInt(3, 7)
                    ps.execute()
                }
            }
            seeded = true
        }
    }
}
