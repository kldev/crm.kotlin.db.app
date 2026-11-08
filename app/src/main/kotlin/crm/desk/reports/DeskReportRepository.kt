package crm.desk.reports

import crm.shared.getInstant
import crm.shared.getInstantOrNull
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository
import java.sql.Types
import java.time.Instant
import java.time.LocalDate

data class CategoryReportRow(
    val number: String,
    val reportedAt: Instant,
    val market: String?,
    val subcategoryKey: String,
    val title: String,
    val requesterIncognito: Boolean,
    val requesterName: String?,
    val status: String,
    val priority: String,
    val assigneeName: String?,
    val handlerName: String?,
    val deadline: Instant,
    val resolvedAt: Instant?,
    val resolvedLate: Boolean,
    /** JSON array of {k, v}, or null. */
    val fields: String?,
)

data class AgentReportRow(
    val name: String,
    /** Taken, resolved, late per period: week, month, three months. */
    val counts: List<Long>,
    val inProgress: Long,
)

/** [from, to) local Warsaw days of the three periods of the agents' report. */
data class ReportPeriods(val week: ClosedRange, val month: ClosedRange, val three: ClosedRange) {
    data class ClosedRange(val from: LocalDate, val until: LocalDate)
}

/** The desk reports (ADR-0010): one `EXEC app.desk_report_*` each. */
@Repository
class DeskReportRepository(private val jdbc: JdbcClient) {

    fun category(
        actorId: Int,
        categoryKey: String,
        from: LocalDate,
        to: LocalDate,
        market: String?,
        subcategoryKey: String?,
        completion: String?,
    ): List<CategoryReportRow> =
        jdbc.sql(
            "EXEC app.desk_report_category @actor_id = :actorId, @category_key = :categoryKey, @from = :from, " +
                "@to = :to, @market = :market, @subcategory_key = :subcategoryKey, @completion = :completion",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("categoryKey", categoryKey, Types.VARCHAR)
            .param("from", from, Types.DATE)
            .param("to", to, Types.DATE)
            .param("market", market, Types.NVARCHAR)
            .param("subcategoryKey", subcategoryKey, Types.VARCHAR)
            .param("completion", completion, Types.VARCHAR)
            .query { rs, _ ->
                CategoryReportRow(
                    number = rs.getString("number"),
                    reportedAt = rs.getInstant("reported_at"),
                    market = rs.getString("market"),
                    subcategoryKey = rs.getString("subcategory_key"),
                    title = rs.getString("title"),
                    requesterIncognito = rs.getBoolean("requester_incognito"),
                    requesterName = rs.getString("requester_name"),
                    status = rs.getString("status"),
                    priority = rs.getString("priority"),
                    assigneeName = rs.getString("assignee_name"),
                    handlerName = rs.getString("handler_name"),
                    deadline = rs.getInstant("deadline"),
                    resolvedAt = rs.getInstantOrNull("resolved_at"),
                    resolvedLate = rs.getBoolean("resolved_late"),
                    fields = rs.getString("fields"),
                )
            }
            .list()

    fun agents(actorId: Int, previous: Boolean): List<AgentReportRow> =
        jdbc.sql("EXEC app.desk_report_agents @actor_id = :actorId, @previous = :previous")
            .param("actorId", actorId, Types.INTEGER)
            .param("previous", previous, Types.BIT)
            .query { rs, _ ->
                AgentReportRow(
                    name = rs.getString("display_name"),
                    counts = listOf(
                        "taken_week", "resolved_week", "late_week", "taken_month", "resolved_month", "late_month",
                        "taken_three", "resolved_three", "late_three",
                    ).map { rs.getLong(it) },
                    inProgress = rs.getLong("in_progress"),
                )
            }
            .list()

    fun periods(actorId: Int, previous: Boolean): ReportPeriods =
        jdbc.sql("EXEC app.desk_report_period_list @actor_id = :actorId, @previous = :previous")
            .param("actorId", actorId, Types.INTEGER)
            .param("previous", previous, Types.BIT)
            .query { rs, _ ->
                fun range(prefix: String) = ReportPeriods.ClosedRange(
                    rs.getObject("${prefix}_from", LocalDate::class.java),
                    rs.getObject("${prefix}_to", LocalDate::class.java),
                )
                ReportPeriods(range("week"), range("month"), range("three"))
            }
            .single()
}
