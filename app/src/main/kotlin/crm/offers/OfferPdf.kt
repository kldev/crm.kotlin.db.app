package crm.offers

import crm.companies.LegalEntityResponse
import crm.desk.reports.Lang
import org.openpdf.text.Chunk
import org.openpdf.text.Document
import org.openpdf.text.Element
import org.openpdf.text.Font
import org.openpdf.text.PageSize
import org.openpdf.text.Paragraph
import org.openpdf.text.Phrase
import org.openpdf.text.Rectangle
import org.openpdf.text.pdf.BaseFont
import org.openpdf.text.pdf.ColumnText
import org.openpdf.text.pdf.PdfPCell
import org.openpdf.text.pdf.PdfPTable
import org.openpdf.text.pdf.PdfPageEventHelper
import org.openpdf.text.pdf.PdfTemplate
import org.openpdf.text.pdf.PdfWriter
import org.springframework.stereotype.Component
import java.awt.Color
import java.io.OutputStream
import java.math.BigDecimal
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * The offer as a PDF in the Obsidian look (ADR-0013): an obsidian band with the company in Cormorant Garamond and a
 * champagne rule, linen surfaces for the table head and the totals, Lato for the text. The closing contact is the
 * author's when they are a salesperson (name, job title, phone, e-mail), otherwise the company's. Every page carries a
 * footer with the company line and "page x of y". The company is the one that signs the offer (ADR-0016).
 */
@Component
class OfferPdf {
    private val obsidian = Color(0x17, 0x1a, 0x21)
    private val champagne = Color(0xc4, 0xa5, 0x74)
    private val champagneSoft = Color(0xf3, 0xeb, 0xdc)
    private val linen = Color(0xf6, 0xf3, 0xee)
    private val text = Color(0x17, 0x1a, 0x21)
    private val textSecondary = Color(0x34, 0x3a, 0x46)
    private val muted = Color(0x58, 0x5b, 0x61)
    private val hairline = Color(0xe8, 0xe4, 0xdc)
    private val bandMuted = Color(0x8d, 0x90, 0x97)
    private val bandText = Color(0xd9, 0xd4, 0xca)

    private val serif: BaseFont by lazy { font("/fonts/CormorantGaramond-SemiBold.ttf") }
    private val sans: BaseFont by lazy { font("/fonts/Lato-Regular.ttf") }
    private val sansBold: BaseFont by lazy { font("/fonts/Lato-Bold.ttf") }

    private fun font(path: String): BaseFont {
        val bytes = javaClass.getResourceAsStream(path)!!.use { it.readAllBytes() }
        return BaseFont.createFont(path.substringAfterLast('/'), BaseFont.IDENTITY_H, BaseFont.EMBEDDED, true, bytes, null)
    }

    fun fileName(offer: OfferResponse) = "oferta-${offer.number.replace('/', '-')}.pdf"

    fun write(offer: OfferResponse, items: List<OfferItemResponse>, company: LegalEntityResponse, lang: Lang, out: OutputStream) {
        val locale = if (lang == Lang.PL) Locale.forLanguageTag("pl-PL") else Locale.UK
        val money = DecimalFormat("#,##0.00", DecimalFormatSymbols(locale))
        val qty = DecimalFormat("#,##0.###", DecimalFormatSymbols(locale))
        val date = DateTimeFormatter.ofPattern("d MMMM yyyy", locale)
        fun amount(v: BigDecimal) = "${money.format(v)} ${offer.currency}"

        val document = Document(PageSize.A4, 42f, 42f, 150f, 64f)
        val writer = PdfWriter.getInstance(document, out)
        writer.pageEvent = Frame(offer, company, lang, date)
        document.addTitle("${offer.number} ${offer.title}")
        document.addAuthor(company.legalName)
        document.open()

        // Title block.
        document.add(Paragraph(offer.templateName(lang).uppercase(locale), Font(sansBold, 7.5f, Font.NORMAL, champagne)).apply {
            spacingAfter = 2f
        })
        document.add(Paragraph(offer.title, Font(serif, 24f, Font.NORMAL, text)).apply { spacingAfter = 14f; leading = 26f })

        // Client and details side by side.
        val parties = PdfPTable(floatArrayOf(1.2f, 1f)).apply { widthPercentage = 100f; setSpacingAfter(16f) }
        parties.addCell(block(lang.t("Dla", "Prepared for"), buildList {
            add(Phrase(offer.clientName, Font(sansBold, 10.5f, Font.NORMAL, text)))
            offer.clientNip?.let { add(small("NIP $it")) }
            offer.clientCity?.let { add(small(it)) }
            offer.clientEmail?.let { add(small(it)) }
        }))
        parties.addCell(block(lang.t("Szczegóły", "Details"), listOf(
            detail(lang.t("Numer", "Number"), offer.number),
            detail(lang.t("Data", "Date"), date.format(offer.createdAt.atZone(ZONE).toLocalDate())),
            detail(lang.t("Ważna do", "Valid until"), date.format(offer.validUntil)),
            detail(lang.t("Waluta", "Currency"), offer.currency),
        )))
        document.add(parties)

        if (offer.intro.isNotBlank()) {
            document.add(Paragraph(offer.intro, Font(sans, 9.5f, Font.NORMAL, textSecondary)).apply {
                leading = 14f
                spacingAfter = 16f
            })
        }

        // Lines.
        val head = Font(sansBold, 7f, Font.NORMAL, muted)
        val cell = Font(sans, 8.5f, Font.NORMAL, text)
        val table = PdfPTable(floatArrayOf(0.35f, 3.1f, 1.0f, 0.8f, 1.15f, 0.55f, 1.25f, 1.3f)).apply {
            widthPercentage = 100f
            headerRows = 1
            setSpacingAfter(10f)
        }
        listOf(
            "#" to Element.ALIGN_LEFT, lang.t("OPIS", "DESCRIPTION") to Element.ALIGN_LEFT,
            lang.t("J.M.", "UNIT") to Element.ALIGN_LEFT, lang.t("ILOŚĆ", "QTY") to Element.ALIGN_RIGHT,
            lang.t("CENA NETTO", "UNIT PRICE") to Element.ALIGN_RIGHT, "VAT" to Element.ALIGN_RIGHT,
            lang.t("NETTO", "NET") to Element.ALIGN_RIGHT, lang.t("BRUTTO", "GROSS") to Element.ALIGN_RIGHT,
        ).forEach { (label, align) ->
            table.addCell(PdfPCell(Phrase(label, head)).apply {
                backgroundColor = linen
                border = Rectangle.BOTTOM
                borderColor = champagne
                borderWidth = 0.8f
                horizontalAlignment = align
                setPadding(6f)
            })
        }
        items.forEach { item ->
            fun c(value: String, align: Int = Element.ALIGN_RIGHT, font: Font = cell) = PdfPCell(Phrase(value, font)).apply {
                border = Rectangle.BOTTOM
                borderColor = hairline
                borderWidth = 0.5f
                horizontalAlignment = align
                verticalAlignment = Element.ALIGN_TOP
                setPadding(6f)
            }
            table.addCell(c(item.lineNo.toString(), Element.ALIGN_LEFT, Font(sans, 8.5f, Font.NORMAL, muted)))
            table.addCell(c(item.description, Element.ALIGN_LEFT))
            table.addCell(c(item.unit, Element.ALIGN_LEFT))
            table.addCell(c(qty.format(item.quantity)))
            table.addCell(c(money.format(item.unitPrice)))
            table.addCell(c("${item.vatRate}%"))
            table.addCell(c(money.format(item.net)))
            table.addCell(c(money.format(item.gross), font = Font(sansBold, 8.5f, Font.NORMAL, text)))
        }
        if (items.isEmpty()) {
            table.addCell(PdfPCell(Phrase(lang.t("Brak pozycji.", "No lines."), cell)).apply { colspan = 8; border = 0; setPadding(8f) })
        }
        document.add(table)

        // Totals on the right, the gross in a champagne box.
        val totals = PdfPTable(floatArrayOf(1.1f, 1.5f)).apply { widthPercentage = 100f }
        fun totalRow(label: String, value: String, strong: Boolean = false) {
            val labelFont = if (strong) Font(sansBold, 9f, Font.NORMAL, text) else Font(sans, 9f, Font.NORMAL, muted)
            val valueFont = if (strong) Font(serif, 15f, Font.NORMAL, text) else Font(sans, 9.5f, Font.NORMAL, text)
            listOf(PdfPCell(Phrase(label, labelFont)), PdfPCell(Phrase(value, valueFont)).apply { horizontalAlignment = Element.ALIGN_RIGHT })
                .forEach {
                    it.border = 0
                    it.setPadding(if (strong) 8f else 4f)
                    it.verticalAlignment = Element.ALIGN_MIDDLE
                    if (strong) it.backgroundColor = champagneSoft
                    totals.addCell(it)
                }
        }
        totalRow(lang.t("Razem netto", "Total net"), amount(offer.totalNet))
        totalRow("VAT", amount(offer.totalVat))
        totalRow(lang.t("Do zapłaty brutto", "Total gross"), amount(offer.totalGross), strong = true)

        // The closing contact: the salesperson's own, or the company's.
        val seller = offer.authorRole == "SALES"
        val contact = PdfPTable(floatArrayOf(0.04f, 1f)).apply { widthPercentage = 100f }
        contact.addCell(PdfPCell().apply { backgroundColor = champagne; border = 0 })
        contact.addCell(PdfPCell().apply {
            border = 0
            backgroundColor = linen
            setPadding(12f)
            addElement(Paragraph(
                if (seller) lang.t("Twój opiekun oferty", "Your contact for this offer") else lang.t("Kontakt", "Contact"),
                Font(sansBold, 7.5f, Font.NORMAL, champagne),
            ))
            if (seller) {
                addElement(Paragraph(offer.authorName, Font(serif, 16f, Font.NORMAL, text)))
                offer.authorJobTitle?.let { addElement(Paragraph(it, Font(sans, 9f, Font.NORMAL, muted))) }
                listOfNotNull(
                    offer.authorPhone?.let { lang.t("Telefon", "Phone") to it },
                    offer.authorEmail?.let { "E-mail" to it },
                ).forEach { (k, v) -> addElement(detailParagraph(k, v)) }
                if (offer.authorPhone == null && offer.authorEmail == null) {
                    company.phone?.let { addElement(detailParagraph(lang.t("Telefon", "Phone"), it)) }
                }
            } else {
                addElement(Paragraph(company.name, Font(serif, 16f, Font.NORMAL, text)))
                listOfNotNull(
                    company.phone?.let { lang.t("Telefon", "Phone") to it },
                    company.email?.let { "E-mail" to it },
                    company.website?.let { "WWW" to it },
                ).forEach { (k, v) -> addElement(detailParagraph(k, v)) }
            }
        })
        // The contact on the left, the totals on the right: one block that is never split between pages.
        val summary = PdfPTable(floatArrayOf(1.15f, 1f)).apply {
            widthPercentage = 100f
            keepTogether = true
            setSpacingAfter(20f)
        }
        summary.addCell(PdfPCell(contact).apply { border = 0; paddingRight = 18f })
        summary.addCell(PdfPCell(totals).apply { border = 0; verticalAlignment = Element.ALIGN_TOP })
        document.add(summary)

        // Terms, one point per line.
        if (offer.terms.isNotBlank()) {
            document.add(Paragraph(lang.t("Warunki", "Terms"), Font(serif, 15f, Font.NORMAL, text)).apply { spacingAfter = 6f })
            offer.terms.lines().filter { it.isNotBlank() }.forEach { line ->
                document.add(Paragraph().apply {
                    add(Chunk("—  ", Font(sans, 9f, Font.NORMAL, champagne)))
                    add(Chunk(line.trim(), Font(sans, 9f, Font.NORMAL, textSecondary)))
                    leading = 13.5f
                    spacingAfter = 3f
                })
            }
        }

        document.close()
    }

    private fun OfferResponse.templateName(lang: Lang) = if (lang == Lang.PL) templateNamePl else templateNameEn

    private fun small(value: String) = Phrase(value, Font(sans, 9f, Font.NORMAL, textSecondary))

    private fun detail(label: String, value: String) = Phrase().apply {
        add(Chunk("$label  ", Font(sans, 8.5f, Font.NORMAL, muted)))
        add(Chunk(value, Font(sansBold, 9f, Font.NORMAL, text)))
    }

    private fun detailParagraph(label: String, value: String) = Paragraph().apply {
        add(Chunk("$label  ", Font(sans, 8.5f, Font.NORMAL, muted)))
        add(Chunk(value, Font(sansBold, 9.5f, Font.NORMAL, text)))
        leading = 14f
    }

    private fun block(title: String, lines: List<Phrase>) = PdfPCell().apply {
        border = Rectangle.TOP
        borderColor = champagne
        borderWidth = 0.8f
        paddingTop = 8f
        paddingRight = 16f
        addElement(Paragraph(title.uppercase(), Font(sansBold, 7f, Font.NORMAL, muted)).apply { spacingAfter = 4f })
        lines.forEach { addElement(Paragraph(it).apply { leading = 13.5f }) }
    }

    /** The band on top of every page and the footer with "page x of y" (the total is filled in when the document closes). */
    private inner class Frame(
        private val offer: OfferResponse,
        private val company: LegalEntityResponse,
        private val lang: Lang,
        private val date: DateTimeFormatter,
    ) :
        PdfPageEventHelper() {
        private lateinit var total: PdfTemplate

        override fun onOpenDocument(writer: PdfWriter, document: Document) {
            total = writer.directContent.createTemplate(40f, 12f)
        }

        override fun onEndPage(writer: PdfWriter, document: Document) {
            val cb = writer.directContent
            val page = document.pageSize
            // The obsidian band with a champagne rule under it.
            cb.saveState()
            cb.setColorFill(obsidian)
            cb.rectangle(0f, page.height - 112f, page.width, 112f)
            cb.fill()
            cb.setColorFill(champagne)
            cb.rectangle(0f, page.height - 114.5f, page.width, 2.5f)
            cb.fill()
            cb.restoreState()
            val left = document.leftMargin()
            val right = page.width - document.rightMargin()
            ColumnText.showTextAligned(cb, Element.ALIGN_LEFT, Phrase(company.name, Font(serif, 26f, Font.NORMAL, Color.WHITE)), left, page.height - 58f, 0f)
            ColumnText.showTextAligned(cb, Element.ALIGN_LEFT, Phrase("${company.legalName}  ·  ${company.address}", Font(sans, 8f, Font.NORMAL, bandMuted)), left, page.height - 76f, 0f)
            ColumnText.showTextAligned(cb, Element.ALIGN_LEFT, Phrase(listOfNotNull("NIP ${company.taxIdFormatted}", company.website).joinToString("  ·  "), Font(sans, 8f, Font.NORMAL, bandMuted)), left, page.height - 88f, 0f)
            ColumnText.showTextAligned(cb, Element.ALIGN_RIGHT, Phrase(lang.t("OFERTA", "OFFER"), Font(sansBold, 7.5f, Font.NORMAL, champagne)), right, page.height - 44f, 0f)
            ColumnText.showTextAligned(cb, Element.ALIGN_RIGHT, Phrase(offer.number, Font(serif, 18f, Font.NORMAL, Color.WHITE)), right, page.height - 64f, 0f)
            ColumnText.showTextAligned(cb, Element.ALIGN_RIGHT, Phrase("${lang.t("ważna do", "valid until")} ${date.format(offer.validUntil)}", Font(sans, 8f, Font.NORMAL, bandText)), right, page.height - 80f, 0f)

            // Footer: a hairline, the company line, page x of y.
            cb.saveState()
            cb.setColorStroke(hairline)
            cb.setLineWidth(0.6f)
            cb.moveTo(left, 44f)
            cb.lineTo(right, 44f)
            cb.stroke()
            cb.restoreState()
            val footer = Font(sans, 7.5f, Font.NORMAL, muted)
            ColumnText.showTextAligned(cb, Element.ALIGN_LEFT, Phrase(listOfNotNull(company.legalName, company.address, company.email).joinToString("  ·  "), footer), left, 32f, 0f)
            val label = "${lang.t("Strona", "Page")} ${writer.pageNumber} ${lang.t("z", "of")} "
            val width = sans.getWidthPoint(label, 7.5f)
            ColumnText.showTextAligned(cb, Element.ALIGN_LEFT, Phrase(label, footer), right - width - 12f, 32f, 0f)
            cb.addTemplate(total, right - 12f, 32f)
        }

        override fun onCloseDocument(writer: PdfWriter, document: Document) {
            ColumnText.showTextAligned(total, Element.ALIGN_LEFT, Phrase((writer.pageNumber - 1).toString(), Font(sans, 7.5f, Font.NORMAL, muted)), 0f, 0f, 0f)
        }
    }

    companion object {
        private val ZONE: ZoneId = ZoneId.of("Europe/Warsaw")
    }
}
