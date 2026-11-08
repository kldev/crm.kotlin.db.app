package crm.offers

import crm.auth.CrmUserDetails
import crm.desk.reports.Lang
import crm.shared.Cursor
import crm.shared.InvalidCursorException
import crm.shared.PageResponse
import crm.shared.RowVersion
import crm.shared.TotalResponse
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.validation.Valid
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import jakarta.validation.constraints.Pattern
import org.springframework.http.ContentDisposition
import org.springframework.http.HttpHeaders
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody
import java.nio.charset.StandardCharsets

/**
 * Offers for clients (ADR-0013): made from a template, edited while a draft, sent, accepted or rejected, printed as a
 * PDF. SALES works only on offers of their own clients; the procedures decide.
 */
@Tag(name = "Offers")
@RestController
@RequestMapping("/api/offers")
class OfferController(private val offers: OfferRepository, private val pdf: OfferPdf) {

    @Operation(summary = "Offer templates: Sales Budownictwo, Sales IT, Sales Outsourcing.")
    @GetMapping("/templates")
    fun listOfferTemplates(@AuthenticationPrincipal actor: CrmUserDetails): List<OfferTemplateResponse> =
        offers.templates(actor.id)

    @Operation(summary = "Offers, newest first. search: the number or a part of the title.")
    @GetMapping
    fun searchOffers(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(required = false) status: String?,
        @RequestParam(required = false) templateKey: String?,
        @RequestParam(required = false) clientId: Long?,
        @RequestParam(required = false) search: String?,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "25") @Min(1) @Max(200) size: Int,
    ): PageResponse<OfferResponse> {
        val afterId = Cursor.decode(cursor, 1)?.let { it[0].toLongOrNull() ?: throw InvalidCursorException("Invalid cursor.") }
        val rows = offers.search(actor.id, OfferFilter(status, templateKey, clientId, search), afterId, size)
        return Cursor.page(rows, size) { Cursor.encode(it.id) }
    }

    @Operation(summary = "Number of offers matching the same filters. Call it only on request.")
    @GetMapping("/count")
    fun countOffers(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(required = false) status: String?,
        @RequestParam(required = false) templateKey: String?,
        @RequestParam(required = false) clientId: Long?,
        @RequestParam(required = false) search: String?,
    ): TotalResponse = TotalResponse(offers.count(actor.id, OfferFilter(status, templateKey, clientId, search)))

    @Operation(summary = "A new draft offer for a client from a template (its texts and lines are copied).")
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    fun createOffer(@AuthenticationPrincipal actor: CrmUserDetails, @Valid @RequestBody body: CreateOfferRequest): OfferResponse =
        offers.create(actor.id, body)

    @Operation(summary = "Offer details with totals.")
    @GetMapping("/{id}")
    fun getOffer(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Long): OfferResponse = offers.get(actor.id, id)

    @Operation(summary = "The lines of an offer with net, VAT and gross.")
    @GetMapping("/{id}/items")
    fun listOfferItems(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Long): List<OfferItemResponse> =
        offers.items(actor.id, id)

    @Operation(summary = "Edit a draft: texts, currency, validity and the whole list of lines. rowVersion required.")
    @PutMapping("/{id}")
    fun updateOffer(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: UpdateOfferRequest,
    ): OfferResponse = offers.update(actor.id, id, body)

    @Operation(summary = "Send, accept, reject, or take a sent offer back to draft.")
    @PostMapping("/{id}/status")
    fun changeOfferStatus(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: ChangeOfferStatusRequest,
    ): OfferResponse = offers.changeStatus(actor.id, id, body.status!!, body.rowVersion!!)

    @Operation(summary = "Delete a draft offer.")
    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun deleteOffer(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @RequestParam @Pattern(regexp = RowVersion.PATTERN) rowVersion: String,
    ) = offers.delete(actor.id, id, rowVersion)

    @Operation(summary = "The offer as a PDF in the Obsidian look; lang pl or en names its labels.")
    @GetMapping("/{id}/pdf")
    fun downloadOfferPdf(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @RequestParam(defaultValue = "pl") lang: String,
        @RequestParam(defaultValue = "false") download: Boolean,
    ): ResponseEntity<StreamingResponseBody> {
        val offer = offers.get(actor.id, id)
        val items = offers.items(actor.id, id)
        val disposition = (if (download) ContentDisposition.attachment() else ContentDisposition.inline())
            .filename(pdf.fileName(offer), StandardCharsets.UTF_8).build()
        return ResponseEntity.ok()
            .contentType(MediaType.APPLICATION_PDF)
            .header(HttpHeaders.CONTENT_DISPOSITION, disposition.toString())
            .header("X-Content-Type-Options", "nosniff")
            .body(StreamingResponseBody { out -> pdf.write(offer, items, Lang.of(lang), out) })
    }
}
