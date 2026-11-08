package crm.monitoring

import crm.shared.getInstant
import crm.shared.getInstantOrNull
import crm.shared.getIntOrNull
import crm.shared.toUtcLocalDateTime
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository
import java.sql.Types
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime

data class HttpSummary(
    val total: Long,
    val ok: Long,
    val redirect: Long,
    val forbidden: Long,
    val notFound: Long,
    val clientError: Long,
    val serverError: Long,
    val avgMs: Double?,
    val p95Ms: Double?,
)

/** Answers in one Warsaw hour or day: 2xx/3xx, 4xx, 5xx. */
data class HttpBucket(val bucket: LocalDateTime, val ok: Long, val clientError: Long, val serverError: Long)

data class HttpCode(val status: Int, val answers: Long, val avgMs: Double?)

data class FailingPath(val method: String, val path: String, val status: Int, val answers: Long, val lastAt: Instant)

data class RequestEntry(
    val id: Long,
    val at: Instant,
    val method: String,
    val path: String,
    val status: Int,
    val elapsedMs: Int,
    val user: String?,
    val traceId: String?,
)

data class LogEntry(
    val id: Long,
    val at: Instant,
    val level: String,
    val source: String,
    val message: String,
    val exception: String?,
    val requestPath: String?,
    val traceId: String?,
)

data class DbOverview(
    val productVersion: String,
    val edition: String,
    val startedAt: LocalDateTime?,
    val serverNow: OffsetDateTime,
    val dataMb: Long?,
    val logMb: Long?,
    val userSessions: Int?,
    val activeRequests: Int?,
    val blockedRequests: Int?,
    val events: Long,
    val lastEventSeq: Long?,
    val lastEventAt: Instant?,
    val tickets: Long,
)

data class DbSession(
    val sessionId: Int,
    val login: String?,
    val host: String?,
    val program: String?,
    val sessionStatus: String?,
    val database: String?,
    val requestStatus: String?,
    val command: String?,
    val waitType: String?,
    val waitMs: Int?,
    val blockingSessionId: Int?,
    val elapsedMs: Int?,
    val openTransactions: Int,
    val lastRequestStart: LocalDateTime?,
    val isBlocking: Boolean,
    val sqlText: String?,
)

data class DbTable(val schema: String, val table: String, val rows: Long, val reservedMb: Double, val dataMb: Double, val indexMb: Double)

/** Monitoring (ADR-0012): one `EXEC app.monitoring_*` per method. */
@Repository
class MonitoringRepository(private val jdbc: JdbcClient) {

    fun writeRequests(json: String): Int =
        jdbc.sql("EXEC app.monitoring_requests_write @rows = :rows").param("rows", json, Types.NVARCHAR)
            .query { rs, _ -> rs.getInt("written") }.single()

    fun writeLogs(json: String): Int =
        jdbc.sql("EXEC app.monitoring_logs_write @rows = :rows").param("rows", json, Types.NVARCHAR)
            .query { rs, _ -> rs.getInt("written") }.single()

    fun cleanup(before: Instant, batchSize: Int): Pair<Long, Long> =
        jdbc.sql("EXEC app.monitoring_cleanup @before = :before, @batch_size = :batch")
            .param("before", before.toUtcLocalDateTime(), Types.TIMESTAMP)
            .param("batch", batchSize, Types.INTEGER)
            .query { rs, _ -> rs.getLong("requests_deleted") to rs.getLong("logs_deleted") }
            .single()

    fun summary(actorId: Int, from: Instant): HttpSummary =
        jdbc.sql("EXEC app.monitoring_http_summary @actor_id = :actorId, @from = :from")
            .param("actorId", actorId, Types.INTEGER)
            .param("from", from.toUtcLocalDateTime(), Types.TIMESTAMP)
            .query { rs, _ ->
                HttpSummary(
                    rs.getLong("total"), rs.getLong("ok"), rs.getLong("redirect"), rs.getLong("forbidden"),
                    rs.getLong("not_found"), rs.getLong("client_error"), rs.getLong("server_error"),
                    rs.getDouble("avg_ms").takeUnless { rs.wasNull() }, rs.getDouble("p95_ms").takeUnless { rs.wasNull() },
                )
            }
            .single()

    fun series(actorId: Int, from: Instant, hourly: Boolean): List<HttpBucket> =
        jdbc.sql("EXEC app.monitoring_http_series @actor_id = :actorId, @from = :from, @hourly = :hourly")
            .param("actorId", actorId, Types.INTEGER)
            .param("from", from.toUtcLocalDateTime(), Types.TIMESTAMP)
            .param("hourly", hourly, Types.BIT)
            .query { rs, _ ->
                HttpBucket(
                    rs.getObject("bucket", LocalDateTime::class.java), rs.getLong("ok"), rs.getLong("client_error"),
                    rs.getLong("server_error"),
                )
            }
            .list()

    fun codes(actorId: Int, from: Instant): List<HttpCode> =
        jdbc.sql("EXEC app.monitoring_http_codes @actor_id = :actorId, @from = :from")
            .param("actorId", actorId, Types.INTEGER)
            .param("from", from.toUtcLocalDateTime(), Types.TIMESTAMP)
            .query { rs, _ -> HttpCode(rs.getInt("status"), rs.getLong("answers"), rs.getDouble("avg_ms").takeUnless { rs.wasNull() }) }
            .list()

    fun failing(actorId: Int, from: Instant): List<FailingPath> =
        jdbc.sql("EXEC app.monitoring_http_failing @actor_id = :actorId, @from = :from")
            .param("actorId", actorId, Types.INTEGER)
            .param("from", from.toUtcLocalDateTime(), Types.TIMESTAMP)
            .query { rs, _ ->
                FailingPath(rs.getString("method"), rs.getString("path"), rs.getInt("status"), rs.getLong("answers"), rs.getInstant("last_at"))
            }
            .list()

    fun requests(actorId: Int, outcome: String?, path: String?, afterId: Long?, size: Int): List<RequestEntry> =
        jdbc.sql(
            "EXEC app.monitoring_request_list @actor_id = :actorId, @outcome = :outcome, @path = :path, " +
                "@after_id = :afterId, @page_size = :size",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("outcome", outcome, Types.VARCHAR)
            .param("path", path, Types.NVARCHAR)
            .param("afterId", afterId, Types.BIGINT)
            .param("size", size, Types.INTEGER)
            .query { rs, _ ->
                RequestEntry(
                    rs.getLong("id"), rs.getInstant("at"), rs.getString("method"), rs.getString("path"), rs.getInt("status"),
                    rs.getInt("elapsed_ms"), rs.getString("user_login"), rs.getString("trace_id"),
                )
            }
            .list()

    fun logs(actorId: Int, level: String?, search: String?, afterId: Long?, size: Int): List<LogEntry> =
        jdbc.sql(
            "EXEC app.monitoring_log_list @actor_id = :actorId, @level = :level, @search = :search, " +
                "@after_id = :afterId, @page_size = :size",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("level", level, Types.VARCHAR)
            .param("search", search, Types.NVARCHAR)
            .param("afterId", afterId, Types.BIGINT)
            .param("size", size, Types.INTEGER)
            .query { rs, _ ->
                LogEntry(
                    rs.getLong("id"), rs.getInstant("at"), rs.getString("level"), rs.getString("source"),
                    rs.getString("message"), rs.getString("exception"), rs.getString("request_path"), rs.getString("trace_id"),
                )
            }
            .list()

    fun overview(actorId: Int): DbOverview =
        jdbc.sql("EXEC app.monitoring_db_overview @actor_id = :actorId")
            .param("actorId", actorId, Types.INTEGER)
            .query { rs, _ ->
                DbOverview(
                    productVersion = rs.getString("product_version"),
                    edition = rs.getString("edition"),
                    startedAt = rs.getObject("started_at_local", LocalDateTime::class.java),
                    serverNow = rs.getObject("server_now", OffsetDateTime::class.java),
                    dataMb = rs.getLong("data_mb").takeUnless { rs.wasNull() },
                    logMb = rs.getLong("log_mb").takeUnless { rs.wasNull() },
                    userSessions = rs.getIntOrNull("user_sessions"),
                    activeRequests = rs.getIntOrNull("active_requests"),
                    blockedRequests = rs.getIntOrNull("blocked_requests"),
                    events = rs.getLong("events"),
                    lastEventSeq = rs.getLong("last_event_seq").takeUnless { rs.wasNull() },
                    lastEventAt = rs.getInstantOrNull("last_event_at"),
                    tickets = rs.getLong("tickets"),
                )
            }
            .single()

    fun sessions(actorId: Int): List<DbSession> =
        jdbc.sql("EXEC app.monitoring_db_sessions @actor_id = :actorId")
            .param("actorId", actorId, Types.INTEGER)
            .query { rs, _ ->
                DbSession(
                    sessionId = rs.getInt("session_id"),
                    login = rs.getString("login_name"),
                    host = rs.getString("host_name"),
                    program = rs.getString("program_name"),
                    sessionStatus = rs.getString("session_status"),
                    database = rs.getString("database_name"),
                    requestStatus = rs.getString("request_status"),
                    command = rs.getString("command"),
                    waitType = rs.getString("wait_type"),
                    waitMs = rs.getIntOrNull("wait_ms"),
                    blockingSessionId = rs.getIntOrNull("blocking_session_id")?.takeIf { it != 0 },
                    elapsedMs = rs.getIntOrNull("elapsed_ms"),
                    openTransactions = rs.getInt("open_transaction_count"),
                    lastRequestStart = rs.getObject("last_request_start_time", LocalDateTime::class.java),
                    isBlocking = rs.getBoolean("is_blocking"),
                    sqlText = rs.getString("sql_text"),
                )
            }
            .list()

    fun tables(actorId: Int): List<DbTable> =
        jdbc.sql("EXEC app.monitoring_db_tables @actor_id = :actorId")
            .param("actorId", actorId, Types.INTEGER)
            .query { rs, _ ->
                DbTable(
                    rs.getString("schema_name"), rs.getString("table_name"), rs.getLong("row_count"),
                    rs.getDouble("reserved_mb"), rs.getDouble("data_mb"), rs.getDouble("index_mb"),
                )
            }
            .list()
}
