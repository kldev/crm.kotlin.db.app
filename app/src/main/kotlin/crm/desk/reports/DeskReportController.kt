package crm.desk.reports

import crm.auth.CrmUserDetails
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import org.springframework.format.annotation.DateTimeFormat
import org.springframework.http.ContentDisposition
import org.springframework.http.HttpHeaders
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody
import java.nio.charset.StandardCharsets
import java.time.LocalDate

/**
 * Desk reports (ADR-0010) for every agent: five category reports with their report data and the agents' work. The
 * page and the exports get the same table; `lang` (pl / en) names its headers and catalog values.
 */
@Tag(name = "Desk reports")
@RestController
@RequestMapping("/api/desk/reports")
class DeskReportController(private val reports: DeskReports, private val exports: ReportExports) {

    @Operation(
        summary = "A category report (kadry-polska, kadry-zagranica, finanse, rekrutacja, marketing): tickets reported " +
            "from..to (Warsaw days, both included) with their report data as columns.",
    )
    @GetMapping("/categories/{slug}")
    fun getCategoryReport(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable slug: String,
        @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) from: LocalDate,
        @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) to: LocalDate,
        @RequestParam(required = false) market: String?,
        @RequestParam(required = false) subcategoryKey: String?,
        @RequestParam(required = false) completion: String?,
        @RequestParam(defaultValue = "pl") lang: String,
    ): ReportTableResponse = ReportTableResponse.from(
        reports.category(actor.id, slug, CategoryFilter(from, to, market, subcategoryKey, completion), Lang.of(lang)),
    )

    @Operation(summary = "The category report as a file: csv, xlsx or pdf.")
    @GetMapping("/categories/{slug}/export.{format}")
    fun exportCategoryReport(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable slug: String,
        @PathVariable format: String,
        @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) from: LocalDate,
        @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) to: LocalDate,
        @RequestParam(required = false) market: String?,
        @RequestParam(required = false) subcategoryKey: String?,
        @RequestParam(required = false) completion: String?,
        @RequestParam(defaultValue = "pl") lang: String,
    ): ResponseEntity<StreamingResponseBody> {
        val language = Lang.of(lang)
        val table = reports.category(actor.id, slug, CategoryFilter(from, to, market, subcategoryKey, completion), language)
        return file(table, format, language)
    }

    @Operation(summary = "The agents' work: taken, resolved and late per agent in this week, month and 3 months.")
    @GetMapping("/agents")
    fun getAgentReport(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(defaultValue = "false") previous: Boolean,
        @RequestParam(defaultValue = "pl") lang: String,
    ): ReportTableResponse = ReportTableResponse.from(reports.agents(actor.id, previous, Lang.of(lang)))

    @Operation(summary = "The agents' work as a file: csv, xlsx or pdf.")
    @GetMapping("/agents/export.{format}")
    fun exportAgentReport(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable format: String,
        @RequestParam(defaultValue = "false") previous: Boolean,
        @RequestParam(defaultValue = "pl") lang: String,
    ): ResponseEntity<StreamingResponseBody> {
        val language = Lang.of(lang)
        return file(reports.agents(actor.id, previous, language), format, language)
    }

    private fun file(table: ReportTable, extension: String, lang: Lang): ResponseEntity<StreamingResponseBody> {
        val format = ExportFormat.of(extension) ?: throw UnknownReportException("export.$extension")
        val disposition = ContentDisposition.attachment().filename(exports.fileName(table, format), StandardCharsets.UTF_8).build()
        return ResponseEntity.ok()
            .contentType(MediaType.parseMediaType(format.contentType))
            .header(HttpHeaders.CONTENT_DISPOSITION, disposition.toString())
            .header("X-Content-Type-Options", "nosniff")
            .body(StreamingResponseBody { out -> exports.write(table, format, lang, out) })
    }
}
