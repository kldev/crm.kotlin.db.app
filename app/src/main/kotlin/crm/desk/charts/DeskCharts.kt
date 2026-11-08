package crm.desk.charts

import crm.shared.getInstant
import crm.shared.getInstantOrNull
import crm.shared.getIntOrNull
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository
import org.springframework.stereotype.Service
import java.sql.Types
import java.time.DayOfWeek
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import kotlin.math.ceil

/** The range of the charts page: the last 7 or 30 Warsaw days by day, or the last 12 weeks (Monday to Sunday). */
enum class ChartRange { DAYS_7, DAYS_30, WEEKS_12 }

data class FlowPoint(
    /** First and last Warsaw day of the bucket, both included. */
    val from: LocalDate,
    val to: LocalDate,
    val reported: Int,
    val resolved: Int,
    val resolvedLate: Int,
    /** Open at the end of the bucket; for the bucket holding now, open now. */
    val openAtEnd: Int,
)

data class KeyFigures(
    val reported: Int,
    val resolved: Int,
    val resolvedLate: Int,
    /** Resolved on time / resolved; null when nothing was resolved. */
    val onTimeShare: Double?,
    val medianResolutionMinutes: Long?,
    val openNow: Int,
    val dueSoonNow: Int,
    val overdueNow: Int,
)

/** Time to resolve as a share of the ticket's SLA (1 = the whole SLA); p90 only from [DeskCharts.MIN_FOR_P90] tickets. */
data class SlaUse(val priority: String, val count: Int, val median: Double?, val p90: Double?, val medianMinutes: Long?)

/** A stacked bar: one value per segment, in the chart's segment order. `label` only where it is not a catalog key. */
data class Breakdown(val key: String, val label: String?, val values: List<Int>)

data class ChartData(
    val range: ChartRange,
    val categoryKey: String?,
    val from: LocalDate,
    val to: LocalDate,
    val generatedAt: Instant,
    val figures: KeyFigures,
    val flow: List<FlowPoint>,
    val sla: List<SlaUse>,
    /** With a category chosen, the breakdown is by its subcategories. */
    val bySubcategory: Boolean,
    /** Segments: resolved on time, resolved late, open. */
    val byCategory: List<Breakdown>,
    /** Segments: on time, due soon, overdue - open tickets now, per priority. */
    val queue: List<Breakdown>,
    /** Segments: resolved on time, resolved late - top 8 agents and the rest. */
    val agents: List<Breakdown>,
    /** Reports per Warsaw weekday (0 = Monday) and hour: 7 rows of 24. */
    val heat: List<List<Int>>,
)

data class ChartTicket(
    val categoryKey: String,
    val subcategoryKey: String,
    val priority: String,
    val status: String,
    val reportedAt: Instant,
    val deadline: Instant,
    val resolvedAt: Instant?,
    val resolvedLate: Boolean,
    val assigneeUserId: Int?,
    val assigneeName: String?,
    val overdue: Boolean,
    val dueSoon: Boolean,
    val weekday: Int,
    val hour: Int,
    val now: Instant,
)

@Repository
class DeskChartRepository(private val jdbc: JdbcClient) {
    fun tickets(actorId: Int, from: LocalDate, to: LocalDate, categoryKey: String?): List<ChartTicket> =
        jdbc.sql(
            "EXEC app.desk_chart_tickets @actor_id = :actorId, @from = :from, @to = :to, @category_key = :categoryKey",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("from", from, Types.DATE)
            .param("to", to, Types.DATE)
            .param("categoryKey", categoryKey, Types.VARCHAR)
            .query { rs, _ ->
                ChartTicket(
                    categoryKey = rs.getString("category_key"),
                    subcategoryKey = rs.getString("subcategory_key"),
                    priority = rs.getString("priority"),
                    status = rs.getString("status"),
                    reportedAt = rs.getInstant("reported_at"),
                    deadline = rs.getInstant("deadline"),
                    resolvedAt = rs.getInstantOrNull("resolved_at"),
                    resolvedLate = rs.getBoolean("resolved_late"),
                    assigneeUserId = rs.getIntOrNull("assignee_user_id"),
                    assigneeName = rs.getString("assignee_name"),
                    overdue = rs.getBoolean("is_overdue"),
                    dueSoon = rs.getBoolean("is_due_soon"),
                    weekday = rs.getInt("report_weekday"),
                    hour = rs.getInt("report_hour"),
                    now = rs.getInstant("now_utc"),
                )
            }
            .list()
}

/**
 * The numbers behind the desk charts (ADR-0011), as Halcyon counted them: one call loads every ticket open at some moment
 * of the range or reported in it, and everything is counted here - fine for a team desk. The deadline states come from
 * the procedure (one rule, one clock); this class only buckets and aggregates.
 */
@Service
class DeskCharts(private val charts: DeskChartRepository) {
    private val zone = ZoneId.of("Europe/Warsaw")
    private val priorities = listOf("CRITICAL", "HIGH", "MEDIUM", "LOW")

    fun build(actorId: Int, range: ChartRange, categoryKey: String?, today: LocalDate = LocalDate.now(zone)): ChartData {
        val buckets = buckets(range, today)
        val first = buckets.first().first
        val last = buckets.last().second.minusDays(1)
        val tickets = charts.tickets(actorId, first, last, categoryKey)
        val now = tickets.firstOrNull()?.now ?: Instant.now()
        val from = start(first)
        val until = start(buckets.last().second)
        fun inRange(at: Instant) = at >= from && at < until

        val reported = tickets.filter { inRange(it.reportedAt) }
        val resolved = tickets.filter { it.resolvedAt != null && inRange(it.resolvedAt) }
        val open = tickets.filter { it.status != "DONE" }

        val flow = buckets.map { (day, next) ->
            val b0 = start(day)
            val b1 = start(next)
            val openAtEnd = if (b1 <= now) {
                tickets.count { it.reportedAt < b1 && (it.resolvedAt == null || it.resolvedAt >= b1) }
            } else {
                // The bucket holding now: open now, so the last point equals the key figure.
                tickets.count { it.reportedAt <= now && it.status != "DONE" }
            }
            FlowPoint(
                from = day,
                to = next.minusDays(1),
                reported = reported.count { it.reportedAt >= b0 && it.reportedAt < b1 },
                resolved = resolved.count { it.resolvedAt!! >= b0 && it.resolvedAt < b1 },
                resolvedLate = resolved.count { it.resolvedLate && it.resolvedAt!! >= b0 && it.resolvedAt < b1 },
                openAtEnd = openAtEnd,
            )
        }

        val figures = KeyFigures(
            reported = reported.size,
            resolved = resolved.size,
            resolvedLate = resolved.count { it.resolvedLate },
            onTimeShare = if (resolved.isEmpty()) null else resolved.count { !it.resolvedLate } / resolved.size.toDouble(),
            medianResolutionMinutes = median(resolved.map { minutes(it.reportedAt, it.resolvedAt!!) })?.toLong(),
            openNow = open.size,
            dueSoonNow = open.count { it.dueSoon },
            overdueNow = open.count { it.overdue },
        )

        val sla = priorities.map { p ->
            val of = resolved.filter { it.priority == p }
            val shares = of.map { minutes(it.reportedAt, it.resolvedAt!!) / minutes(it.reportedAt, it.deadline) }
            SlaUse(
                priority = p,
                count = of.size,
                median = median(shares),
                p90 = if (of.size >= MIN_FOR_P90) percentile(shares, 0.9) else null,
                medianMinutes = median(of.map { minutes(it.reportedAt, it.resolvedAt!!) })?.toLong(),
            )
        }

        val bySubcategory = categoryKey != null
        val byCategory = reported.groupBy { if (bySubcategory) it.subcategoryKey else it.categoryKey }
            .map { (key, group) ->
                Breakdown(
                    key, null,
                    listOf(
                        group.count { it.status == "DONE" && !it.resolvedLate },
                        group.count { it.status == "DONE" && it.resolvedLate },
                        group.count { it.status != "DONE" },
                    ),
                )
            }
            .sortedWith(compareByDescending<Breakdown> { it.values.sum() }.thenBy { it.key })

        val queue = priorities.map { p ->
            val of = open.filter { it.priority == p }
            Breakdown(p, null, listOf(of.count { !it.overdue && !it.dueSoon }, of.count { it.dueSoon }, of.count { it.overdue }))
        }

        var agents = resolved.groupBy { it.assigneeUserId to (it.assigneeName ?: "?") }
            .map { (agent, group) ->
                Breakdown(agent.first?.toString() ?: "", agent.second, listOf(group.count { !it.resolvedLate }, group.count { it.resolvedLate }))
            }
            .sortedWith(compareByDescending<Breakdown> { it.values.sum() }.thenBy { it.label })
        if (agents.size > TOP_AGENTS + 1) {
            val rest = agents.drop(TOP_AGENTS)
            agents = agents.take(TOP_AGENTS) +
                Breakdown("rest", rest.size.toString(), listOf(rest.sumOf { it.values[0] }, rest.sumOf { it.values[1] }))
        }

        val heat = List(7) { IntArray(24) }
        reported.forEach { heat[it.weekday][it.hour]++ }

        return ChartData(
            range, categoryKey, first, last, now, figures, flow, sla, bySubcategory, byCategory, queue, agents,
            heat.map { it.toList() },
        )
    }

    private fun start(day: LocalDate): Instant = day.atStartOfDay(zone).toInstant()

    private fun minutes(from: Instant, to: Instant) = Duration.between(from, to).toSeconds() / 60.0

    /** [first day, the day after the last) of each bucket. */
    private fun buckets(range: ChartRange, today: LocalDate): List<Pair<LocalDate, LocalDate>> = when (range) {
        ChartRange.DAYS_7 -> (6 downTo 0).map { today.minusDays(it.toLong()) }.map { it to it.plusDays(1) }
        ChartRange.DAYS_30 -> (29 downTo 0).map { today.minusDays(it.toLong()) }.map { it to it.plusDays(1) }
        ChartRange.WEEKS_12 -> {
            val monday = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
            (11 downTo 0).map { monday.minusWeeks(it.toLong()) }.map { it to it.plusWeeks(1) }
        }
    }

    companion object {
        const val MIN_FOR_P90 = 5
        const val TOP_AGENTS = 8

        fun median(values: List<Double>): Double? {
            if (values.isEmpty()) return null
            val sorted = values.sorted()
            val mid = sorted.size / 2
            return if (sorted.size % 2 == 1) sorted[mid] else (sorted[mid - 1] + sorted[mid]) / 2
        }

        /** The nearest rank: the smallest value with at least [p] of the values at or below it. */
        fun percentile(values: List<Double>, p: Double): Double? {
            if (values.isEmpty()) return null
            val sorted = values.sorted()
            val rank = ceil(p * sorted.size).toInt().coerceIn(1, sorted.size)
            return sorted[rank - 1]
        }
    }
}
