package crm.shared

import org.springframework.boot.health.contributor.Health
import org.springframework.boot.health.contributor.HealthIndicator
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Component

/** Database readiness through the same path as every other call: `EXEC app.health_ping`. */
@Component("database")
class DatabaseHealthIndicator(private val jdbc: JdbcClient) : HealthIndicator {
    override fun health(): Health = try {
        jdbc.sql("EXEC app.health_ping").query { rs, _ -> rs.getBoolean("ok") }.single()
        Health.up().build()
    } catch (error: Exception) {
        Health.down().withDetail("error", error.javaClass.simpleName).build()
    }
}
