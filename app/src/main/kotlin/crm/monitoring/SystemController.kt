package crm.monitoring

import crm.auth.CrmUserDetails
import crm.shared.Cursor
import crm.shared.DatabaseHealthIndicator
import crm.shared.InvalidCursorException
import crm.shared.PageResponse
import crm.storage.StorageHealthIndicator
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication
import org.springframework.core.env.Environment
import org.springframework.http.HttpStatus
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.server.ResponseStatusException
import java.lang.management.ManagementFactory
import java.time.Duration
import java.time.Instant

enum class StatusRange(val duration: Duration, val hourly: Boolean) {
    H24(Duration.ofHours(24), true),
    D7(Duration.ofDays(7), false),
    D14(Duration.ofDays(14), false),
}

data class SettingResponse(val variable: String, val value: String?, val description: String)

data class SystemStatus(
    val startedAt: Instant,
    val uptimeSeconds: Long,
    val javaVersion: String,
    val database: String,
    val storage: String,
    val summary: HttpSummary,
    val series: List<HttpBucket>,
    val codes: List<HttpCode>,
    val failing: List<FailingPath>,
    val settings: List<SettingResponse>,
)

data class QueueState(val name: String, val waiting: Int, val capacity: Int, val dropped: Long)

data class QueuesResponse(
    val queues: List<QueueState>,
    val jobs: List<JobState>,
    val written: Long,
    val failed: Long,
)

data class DatabaseResponse(val overview: DbOverview, val sessions: List<DbSession>, val tables: List<DbTable>)

/**
 * The system pages (ADR-0012), administrators only (Spring Security and the procedures): status of the application and
 * its HTTP answers, the log, the database and the in-memory queues with their background jobs.
 */
@Tag(name = "System")
@RestController
@ConditionalOnWebApplication
@RequestMapping("/api/system")
class SystemController(
    private val monitoring: MonitoringRepository,
    private val queue: MonitoringQueue,
    private val writer: MonitoringWriter,
    private val cleanup: MonitoringCleanup,
    private val database: DatabaseHealthIndicator,
    private val storage: StorageHealthIndicator,
    private val environment: Environment,
) {
    @Operation(summary = "Application status: health, HTTP answers in the range, codes, failing paths, effective settings.")
    @GetMapping("/status")
    fun getSystemStatus(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(defaultValue = "H24") range: StatusRange,
    ): SystemStatus {
        val from = Instant.now().minus(range.duration)
        val runtime = ManagementFactory.getRuntimeMXBean()
        return SystemStatus(
            startedAt = Instant.ofEpochMilli(runtime.startTime),
            uptimeSeconds = runtime.uptime / 1000,
            javaVersion = Runtime.version().toString(),
            database = database.health().status.code,
            storage = storage.health().status.code,
            summary = monitoring.summary(actor.id, from),
            series = monitoring.series(actor.id, from, range.hourly),
            codes = monitoring.codes(actor.id, from),
            failing = monitoring.failing(actor.id, from),
            settings = settings(),
        )
    }

    @Operation(summary = "Recorded HTTP answers, newest first. outcome: OK, REDIRECT, FORBIDDEN, NOT_FOUND, CLIENT, SERVER.")
    @GetMapping("/requests")
    fun listRecordedRequests(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(required = false) outcome: String?,
        @RequestParam(required = false) path: String?,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "50") @Min(1) @Max(200) size: Int,
    ): PageResponse<RequestEntry> {
        val after = afterId(cursor)
        return Cursor.page(monitoring.requests(actor.id, outcome, path, after, size), size) { Cursor.encode(it.id) }
    }

    @Operation(summary = "The application's log, newest first. level: the lowest level shown (INFO, WARN, ERROR).")
    @GetMapping("/logs")
    fun listLogEntries(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(required = false) level: String?,
        @RequestParam(required = false) search: String?,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "50") @Min(1) @Max(200) size: Int,
    ): PageResponse<LogEntry> {
        val after = afterId(cursor)
        return Cursor.page(monitoring.logs(actor.id, level, search, after, size), size) { Cursor.encode(it.id) }
    }

    @Operation(summary = "The database: server, size, sessions now (blocking marked), tables, the event store.")
    @GetMapping("/database")
    fun getDatabaseState(@AuthenticationPrincipal actor: CrmUserDetails): DatabaseResponse =
        DatabaseResponse(monitoring.overview(actor.id), monitoring.sessions(actor.id), monitoring.tables(actor.id))

    @Operation(summary = "The monitoring queues and the background jobs.")
    @GetMapping("/queues")
    fun getQueues(@AuthenticationPrincipal actor: CrmUserDetails): QueuesResponse {
        monitoring.summary(actor.id, Instant.now()) // the procedure checks the administrator
        return QueuesResponse(
            queues = listOf(
                QueueState("requests", queue.requests.size, queue.capacity, queue.droppedRequests.get()),
                QueueState("logs", queue.logs.size, queue.capacity, queue.droppedLogs.get()),
            ),
            jobs = listOf(writer.tracker.state(), cleanup.tracker.state()),
            written = writer.written.get(),
            failed = writer.failed.get(),
        )
    }

    @Operation(summary = "Run a background job now: writer or cleanup.")
    @PostMapping("/jobs/{name}/run")
    fun runJob(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable name: String): JobState {
        monitoring.summary(actor.id, Instant.now())
        return when (name) {
            "writer" -> writer.flush().let { writer.tracker.state() }
            "cleanup" -> cleanup.run().let { cleanup.tracker.state() }
            else -> throw ResponseStatusException(HttpStatus.NOT_FOUND)
        }
    }

    private fun afterId(cursor: String?) =
        Cursor.decode(cursor, 1)?.let { it[0].toLongOrNull() ?: throw InvalidCursorException("Invalid cursor.") }

    /** The technical settings as the application runs with them - never a secret. */
    private fun settings(): List<SettingResponse> = listOf(
        Triple("CRM_DB_POOL_SIZE", "spring.datasource.hikari.maximum-pool-size", "Database connections"),
        Triple("CRM_SESSION_TIMEOUT", "server.servlet.session.timeout", "Session idle timeout"),
        Triple("CRM_LOGIN_MAX_FAILED", "crm.auth.max-failed-logins", "Failed logins before a lock"),
        Triple("CRM_LOGIN_LOCK_MINUTES", "crm.auth.lock-minutes", "Lock length in minutes"),
        Triple("CRM_DEV_LOGIN", "crm.auth.dev-login", "One-click development login"),
        Triple("CRM_DESK_PUBLIC_REPORTS_PER_MINUTE", "crm.desk.public-reports-per-minute", "Public form tickets per minute"),
        Triple("CRM_S3_ENDPOINT", "crm.storage.endpoint", "Attachments storage"),
        Triple("CRM_S3_BUCKET", "crm.storage.bucket", "Attachments bucket"),
        Triple("CRM_MONITORING_ENABLED", "crm.monitoring.enabled", "Monitoring on"),
        Triple("CRM_MONITORING_QUEUE_CAPACITY", "crm.monitoring.queue-capacity", "Entries waiting per queue"),
        Triple("CRM_MONITORING_FLUSH_INTERVAL", "crm.monitoring.flush-interval", "Write interval"),
        Triple("CRM_MONITORING_RETENTION", "crm.monitoring.retention", "Kept for"),
        Triple("CRM_MONITORING_CLEANUP_INTERVAL", "crm.monitoring.cleanup-interval", "Cleanup interval"),
        Triple("CRM_MONITORING_LOG_LEVEL", "crm.monitoring.log-level", "Lowest level logged to the table"),
    ).map { (variable, property, description) -> SettingResponse(variable, environment.getProperty(property), description) }
}
