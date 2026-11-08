package crm.monitoring

import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import jakarta.validation.constraints.Pattern
import org.springframework.boot.context.properties.ConfigurationProperties
import org.springframework.validation.annotation.Validated
import java.time.Duration

/**
 * Monitoring settings (ADR-0012), technical, so environment only and checked at start (CRM_MONITORING_*). The status
 * page shows them read-only with their variable names.
 */
@Validated
@ConfigurationProperties("crm.monitoring")
data class MonitoringProperties(
    val enabled: Boolean = true,
    /** Entries waiting per queue; when full, new ones are dropped and counted (a slow database never slows a page). */
    @field:Min(100) @field:Max(1_000_000) val queueCapacity: Int = 10_000,
    val flushInterval: Duration = Duration.ofSeconds(2),
    @field:Min(10) @field:Max(5_000) val writeBatchSize: Int = 500,
    val retention: Duration = Duration.ofDays(14),
    val cleanupInterval: Duration = Duration.ofHours(1),
    @field:Min(100) @field:Max(100_000) val cleanupBatchSize: Int = 5_000,
    /** The lowest level written to the log table. */
    @field:Pattern(regexp = "INFO|WARN|ERROR") val logLevel: String = "INFO",
    /** Path prefixes not recorded: probes and static files. */
    val ignoredPaths: List<String> = listOf("/actuator", "/assets/", "/favicon", "/fonts/"),
)
