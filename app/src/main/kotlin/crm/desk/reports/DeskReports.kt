package crm.desk.reports

import crm.desk.DeskRepository
import crm.desk.FieldDefinitionResponse
import org.springframework.stereotype.Service
import tools.jackson.databind.json.JsonMapper
import java.math.BigDecimal
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/** A category report: its slug in URLs (as in Halcyon) and the category it reads. */
enum class CategoryReport(val slug: String, val categoryKey: String) {
    HR_POLAND("kadry-polska", "hr-poland"),
    HR_ABROAD("kadry-zagranica", "hr-abroad"),
    FINANCE("finanse", "finance"),
    RECRUITMENT("rekrutacja", "recruitment"),
    MARKETING("marketing", "marketing"),
    ;

    companion object {
        fun of(slug: String) = entries.firstOrNull { it.slug == slug }
    }
}

class UnknownReportException(slug: String) : RuntimeException("Unknown report: $slug")

data class CategoryFilter(
    val from: LocalDate,
    val to: LocalDate,
    val market: String?,
    val subcategoryKey: String?,
    val completion: String?,
)

/**
 * Builds the desk reports (ADR-0010) as [ReportTable]s - the page and the exports show the same table. The data and
 * its rules come from the procedures; this class names the columns, pivots the report fields into columns (only the
 * fields that have a value in at least one row, in catalog order) and translates catalog values for English.
 */
@Service
class DeskReports(
    private val desk: DeskRepository,
    private val reports: DeskReportRepository,
    private val names: CatalogNames,
    private val json: JsonMapper,
) {
    fun category(actorId: Int, slug: String, filter: CategoryFilter, lang: Lang): ReportTable {
        val report = CategoryReport.of(slug) ?: throw UnknownReportException(slug)
        val catalog = desk.catalog()
        val category = catalog.categories.first { it.key == report.categoryKey }
        val subs = category.subcategories.associateBy { it.key }
        val definitions = category.subcategories.flatMap { it.fields }.distinctBy { it.key }
        val rows = reports.category(
            actorId, report.categoryKey, filter.from, filter.to, filter.market, filter.subcategoryKey, filter.completion,
        )
        val values = rows.map { row ->
            row.fields?.let { text -> json.readTree(text).associate { it["k"].asString() to it["v"].asString() } }.orEmpty()
        }
        val used = definitions.filter { d -> values.any { it.containsKey(d.key) } }
        val hasMarkets = category.subcategories.any { it.market != null }

        val columns = buildList {
            add(ReportColumn("number", lang.t("Numer", "Number")))
            add(ReportColumn("reported", lang.t("Data zgłoszenia", "Reported"), CellKind.DATETIME))
            if (hasMarkets) add(ReportColumn("market", lang.t("Rynek", "Market")))
            add(ReportColumn("subcategory", lang.t("Podkategoria", "Subcategory")))
            add(ReportColumn("title", lang.t("Tytuł", "Title")))
            add(ReportColumn("requester", lang.t("Zgłaszający", "Requester")))
            add(ReportColumn("status", lang.t("Status", "Status")))
            add(ReportColumn("priority", lang.t("Priorytet", "Priority")))
            add(ReportColumn("agent", lang.t("Agent", "Agent")))
            add(ReportColumn("handler", lang.t("Osoba realizująca", "Person doing the work")))
            add(ReportColumn("deadline", lang.t("Termin", "Deadline"), CellKind.DATETIME))
            add(ReportColumn("resolved", lang.t("Zrealizowano", "Resolved"), CellKind.DATETIME))
            used.forEach { add(ReportColumn("field:${it.key}", names.n(it.label, lang), kindOf(it))) }
        }
        val table = rows.mapIndexed { i, row ->
            buildList<Any?> {
                add(row.number)
                add(row.reportedAt)
                if (hasMarkets) add(row.market?.let { names.n(it, lang) })
                add(subs[row.subcategoryKey]?.name?.let { names.n(it, lang) } ?: row.subcategoryKey)
                add(row.title)
                add(if (row.requesterIncognito) "incognito" else row.requesterName)
                add(statusLabel(row.status, row.resolvedLate, lang))
                add(priorityLabel(row.priority, lang))
                add(row.assigneeName)
                add(row.handlerName)
                add(row.deadline)
                add(row.resolvedAt)
                used.forEach { add(cell(it, values[i][it.key], lang)) }
            }
        }
        return ReportTable(
            slug = report.slug,
            title = names.n(category.name, lang),
            subtitle = period(filter.from, filter.to, lang),
            columns = columns,
            rows = table,
        )
    }

    fun agents(actorId: Int, previous: Boolean, lang: Lang): ReportTable {
        val periods = reports.periods(actorId, previous)
        val rows = reports.agents(actorId, previous)
        val groups = listOf(
            lang.t("Tydzień", "Week") to periods.week,
            lang.t("Miesiąc", "Month") to periods.month,
            lang.t("3 miesiące", "3 months") to periods.three,
        )
        val columns = buildList {
            add(ReportColumn("agent", lang.t("Agent", "Agent")))
            groups.forEachIndexed { i, (name, range) ->
                val group = "$name ${period(range.from, range.until.minusDays(1), lang)}"
                add(ReportColumn("taken:$i", lang.t("Przejęte", "Taken"), CellKind.NUMBER, group))
                add(ReportColumn("resolved:$i", lang.t("Zrealizowane", "Resolved"), CellKind.NUMBER, group))
                add(ReportColumn("late:$i", lang.t("Po terminie", "Late"), CellKind.NUMBER, group))
            }
            add(ReportColumn("inProgress", lang.t("W realizacji teraz", "In progress now"), CellKind.NUMBER))
        }
        val table = rows.map { row -> listOf<Any?>(row.name) + row.counts + row.inProgress }
        val totals = listOf<Any?>(lang.t("Razem", "Total")) +
            (0 until 9).map { c -> rows.sumOf { it.counts[c] } } + rows.sumOf { it.inProgress }
        return ReportTable(
            slug = "agenci",
            title = lang.t("Praca agentów", "Agents' work"),
            subtitle = if (previous) lang.t("Poprzednie okresy", "Previous periods") else lang.t("Bieżące okresy", "Current periods"),
            columns = columns,
            rows = table,
            totals = totals,
        )
    }

    private fun kindOf(field: FieldDefinitionResponse) = when (field.kind) {
        "DATE" -> CellKind.DATE
        "AMOUNT" -> CellKind.AMOUNT
        "COUNT" -> CellKind.NUMBER
        else -> CellKind.TEXT
    }

    /** A stored value as its typed cell; choices are translated for English, what people typed is not. */
    private fun cell(field: FieldDefinitionResponse, value: String?, lang: Lang): Any? = when {
        value == null -> null
        field.kind == "DATE" -> LocalDate.parse(value)
        field.kind == "AMOUNT" -> BigDecimal(value)
        field.kind == "COUNT" -> value.toLong()
        field.kind == "CHOICE" -> names.n(value, lang)
        field.kind == "MULTI_CHOICE" -> value.split(", ").joinToString(", ") { names.n(it, lang) }
        else -> value
    }

    companion object {
        fun statusLabel(status: String, late: Boolean, lang: Lang) = when (status) {
            "IN_POOL" -> lang.t("W puli", "In the pool")
            "IN_PROGRESS" -> lang.t("W realizacji", "In progress")
            else -> if (late) lang.t("Zrealizowane po terminie", "Resolved late") else lang.t("Zrealizowane", "Resolved")
        }

        fun priorityLabel(priority: String, lang: Lang) = when (priority) {
            "CRITICAL" -> lang.t("Krytyczny", "Critical")
            "HIGH" -> lang.t("Wysoki", "High")
            "MEDIUM" -> lang.t("Średni", "Medium")
            else -> lang.t("Niski", "Low")
        }

        /** "2–8 lis 2026" / "2–8 Nov 2026", both days included. */
        fun period(from: LocalDate, to: LocalDate, lang: Lang): String {
            val locale = if (lang == Lang.PL) Locale.forLanguageTag("pl-PL") else Locale.UK
            val full = DateTimeFormatter.ofPattern("d MMM yyyy", locale)
            return if (from == to) full.format(from) else "${DateTimeFormatter.ofPattern("d MMM", locale).format(from)} – ${full.format(to)}"
        }
    }
}
