package crm.desk.reports

import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate

/** Polish (the default) or English: the language of a report's headers, catalog names and exports (ADR-0008). */
enum class Lang {
    PL, EN;

    fun t(pl: String, en: String) = if (this == PL) pl else en

    companion object {
        fun of(value: String?) = if (value.equals("en", ignoreCase = true)) EN else PL
    }
}

/** How a cell is typed: exports write real dates and numbers, the page formats them. */
enum class CellKind { TEXT, DATE, DATETIME, NUMBER, AMOUNT }

/** A column; `group` is the header above it (a period of the agents' report). */
data class ReportColumn(val key: String, val label: String, val kind: CellKind = CellKind.TEXT, val group: String? = null)

/**
 * The one table a report page shows and every export writes (ADR-0010): typed cells - String, LocalDate, Instant
 * (shown in Warsaw time), Long, BigDecimal - or null.
 */
data class ReportTable(
    val slug: String,
    val title: String,
    val subtitle: String,
    val columns: List<ReportColumn>,
    val rows: List<List<Any?>>,
    /** A last row of totals (the agents' report). */
    val totals: List<Any?>? = null,
)

data class ReportColumnResponse(val key: String, val label: String, val kind: String, val group: String?)

/** A report for the page: cells as text (ISO dates and instants, plain numbers); `kind` says how to show them. */
data class ReportTableResponse(
    val slug: String,
    val title: String,
    val subtitle: String,
    val columns: List<ReportColumnResponse>,
    val rows: List<List<String?>>,
    val totals: List<String?>?,
) {
    companion object {
        fun from(table: ReportTable) = ReportTableResponse(
            table.slug,
            table.title,
            table.subtitle,
            table.columns.map { ReportColumnResponse(it.key, it.label, it.kind.name, it.group) },
            table.rows.map { row -> row.map(::text) },
            table.totals?.map(::text),
        )

        private fun text(value: Any?): String? = when (value) {
            null -> null
            is BigDecimal -> value.toPlainString()
            is Instant, is LocalDate -> value.toString()
            else -> value.toString()
        }
    }
}
