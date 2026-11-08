package crm.desk.reports

import org.apache.poi.ss.usermodel.FillPatternType
import org.apache.poi.ss.usermodel.IndexedColors
import org.apache.poi.ss.util.CellRangeAddress
import org.apache.poi.xssf.usermodel.XSSFWorkbook
import org.openpdf.text.Document
import org.openpdf.text.Element
import org.openpdf.text.Font
import org.openpdf.text.PageSize
import org.openpdf.text.Paragraph
import org.openpdf.text.Phrase
import org.openpdf.text.pdf.BaseFont
import org.openpdf.text.pdf.PdfPCell
import org.openpdf.text.pdf.PdfPTable
import org.openpdf.text.pdf.PdfWriter
import org.springframework.stereotype.Component
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.math.BigDecimal
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

enum class ExportFormat(val extension: String, val contentType: String) {
    CSV("csv", "text/csv; charset=UTF-8"),
    XLSX("xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
    PDF("pdf", "application/pdf"),
    ;

    companion object {
        fun of(extension: String) = entries.firstOrNull { it.extension == extension.lowercase() }
    }
}

/**
 * Writes a [ReportTable] as CSV, XLSX or PDF (ADR-0010), the same table the page shows. Times in Warsaw.
 *  - CSV for a Polish Excel: `;`, UTF-8 with BOM, CRLF, decimal comma, and a `'` before a value starting with
 *    = + - @ (a formula a spreadsheet would otherwise run).
 *  - XLSX: real dates and numbers, a frozen header row with an autofilter.
 *  - PDF: A4 landscape, A3 for more than 13 columns, the header repeated on every page, Lato embedded.
 */
@Component
class ReportExports {
    private val zone = ZoneId.of("Europe/Warsaw")
    private val dateTime = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")

    fun fileName(table: ReportTable, format: ExportFormat) =
        "raport-${table.slug}-${LocalDate.now(zone)}.${format.extension}"

    fun write(table: ReportTable, format: ExportFormat, lang: Lang, out: OutputStream) = when (format) {
        ExportFormat.CSV -> csv(table, lang, out)
        ExportFormat.XLSX -> xlsx(table, out)
        ExportFormat.PDF -> pdf(table, lang, out)
    }

    private fun rowsWithTotals(table: ReportTable) = table.rows + listOfNotNull(table.totals)

    private fun header(column: ReportColumn) = column.group?.let { "$it: ${column.label}" } ?: column.label

    // ---------------------------------------------------------------- CSV

    private fun csv(table: ReportTable, lang: Lang, out: OutputStream) {
        val decimal = DecimalFormat("0.00", DecimalFormatSymbols(Locale.forLanguageTag("pl-PL")))
        val text = StringBuilder("﻿")
        fun line(cells: List<String>) = text.append(cells.joinToString(";") { quote(guard(it)) }).append("\r\n")
        line(table.columns.map(::header))
        rowsWithTotals(table).forEach { row ->
            line(row.map { value ->
                when (value) {
                    null -> ""
                    is Instant -> dateTime.format(value.atZone(zone))
                    is LocalDate -> value.toString()
                    is BigDecimal -> decimal.format(value)
                    else -> value.toString()
                }
            })
        }
        out.write(text.toString().toByteArray(Charsets.UTF_8))
    }

    /** A value a spreadsheet would read as a formula gets a leading apostrophe. */
    private fun guard(value: String) = if (value.isNotEmpty() && value[0] in "=+-@\t\r") "'$value" else value

    private fun quote(value: String) =
        if (value.any { it == ';' || it == '"' || it == '\n' || it == '\r' }) "\"${value.replace("\"", "\"\"")}\"" else value

    // ---------------------------------------------------------------- XLSX

    private fun xlsx(table: ReportTable, out: OutputStream) {
        XSSFWorkbook().use { book ->
            val sheet = book.createSheet(table.title.take(31).replace(Regex("[\\[\\]*?/\\\\:]"), " "))
            val helper = book.creationHelper
            val bold = book.createFont().apply { bold = true }
            val head = book.createCellStyle().apply {
                setFont(bold)
                fillForegroundColor = IndexedColors.GREY_25_PERCENT.index
                fillPattern = FillPatternType.SOLID_FOREGROUND
            }
            val dateStyle = book.createCellStyle().apply { dataFormat = helper.createDataFormat().getFormat("yyyy-mm-dd") }
            val timeStyle = book.createCellStyle().apply { dataFormat = helper.createDataFormat().getFormat("yyyy-mm-dd hh:mm") }
            val moneyStyle = book.createCellStyle().apply { dataFormat = helper.createDataFormat().getFormat("#,##0.00") }
            val totalStyle = book.createCellStyle().apply { setFont(bold) }

            val header = sheet.createRow(0)
            table.columns.forEachIndexed { c, column ->
                header.createCell(c).apply {
                    setCellValue(header(column))
                    cellStyle = head
                }
            }
            rowsWithTotals(table).forEachIndexed { r, values ->
                val row = sheet.createRow(r + 1)
                values.forEachIndexed { c, value ->
                    val cell = row.createCell(c)
                    when (value) {
                        null -> {}
                        is Instant -> {
                            cell.setCellValue(LocalDateTime.ofInstant(value, zone))
                            cell.cellStyle = timeStyle
                        }
                        is LocalDate -> {
                            cell.setCellValue(value)
                            cell.cellStyle = dateStyle
                        }
                        is BigDecimal -> {
                            cell.setCellValue(value.toDouble())
                            cell.cellStyle = moneyStyle
                        }
                        is Number -> cell.setCellValue(value.toDouble())
                        else -> cell.setCellValue(value.toString())
                    }
                    if (table.totals != null && r == table.rows.size) cell.cellStyle = totalStyle
                }
            }
            sheet.createFreezePane(0, 1)
            if (table.columns.isNotEmpty()) {
                sheet.setAutoFilter(CellRangeAddress(0, maxOf(table.rows.size, 1), 0, table.columns.size - 1))
            }
            table.columns.indices.forEach { c ->
                val longest = (listOf(header(table.columns[c])) + table.rows.map { it[c]?.toString() ?: "" }).maxOf { it.length }
                sheet.setColumnWidth(c, (minOf(maxOf(longest, 8), 50) + 2) * 256)
            }
            book.write(out)
        }
    }

    // ---------------------------------------------------------------- PDF

    private val regular: BaseFont by lazy { font("/fonts/Lato-Regular.ttf") }
    private val boldFont: BaseFont by lazy { font("/fonts/Lato-Bold.ttf") }

    private fun font(path: String): BaseFont {
        val bytes = javaClass.getResourceAsStream(path)!!.use { it.readAllBytes() }
        return BaseFont.createFont(path.substringAfterLast('/'), BaseFont.IDENTITY_H, BaseFont.EMBEDDED, true, bytes, null)
    }

    private fun pdf(table: ReportTable, lang: Lang, out: OutputStream) {
        val size = if (table.columns.size > 13) PageSize.A3.rotate() else PageSize.A4.rotate()
        val buffer = ByteArrayOutputStream()
        val document = Document(size, 24f, 24f, 28f, 28f)
        PdfWriter.getInstance(document, buffer)
        document.open()
        document.add(Paragraph(table.title, Font(boldFont, 16f)))
        document.add(Paragraph(table.subtitle, Font(regular, 10f)).apply { spacingAfter = 10f })

        val cellFont = Font(regular, 7.5f)
        val headFont = Font(boldFont, 7.5f)
        val locale = if (lang == Lang.PL) Locale.forLanguageTag("pl-PL") else Locale.UK
        val decimal = DecimalFormat("#,##0.00", DecimalFormatSymbols(locale))
        val grid = PdfPTable(maxOf(table.columns.size, 1)).apply {
            widthPercentage = 100f
            headerRows = 1
        }
        table.columns.forEach { column ->
            grid.addCell(PdfPCell(Phrase(header(column), headFont)).apply { grayFill = 0.9f; setPadding(3f) })
        }
        rowsWithTotals(table).forEachIndexed { r, row ->
            val isTotal = table.totals != null && r == table.rows.size
            row.forEach { value ->
                val text = when (value) {
                    null -> ""
                    is Instant -> dateTime.format(value.atZone(zone))
                    is LocalDate -> value.toString()
                    is BigDecimal -> decimal.format(value)
                    else -> value.toString()
                }
                grid.addCell(PdfPCell(Phrase(text, if (isTotal) headFont else cellFont)).apply {
                    setPadding(3f)
                    if (value is Number) horizontalAlignment = Element.ALIGN_RIGHT
                })
            }
        }
        if (table.rows.isEmpty()) {
            grid.addCell(PdfPCell(Phrase(lang.t("Brak zgłoszeń w tym okresie.", "No tickets in this period."), cellFont)).apply {
                colspan = maxOf(table.columns.size, 1)
            })
        }
        document.add(grid)
        document.close()
        buffer.writeTo(out)
    }
}
