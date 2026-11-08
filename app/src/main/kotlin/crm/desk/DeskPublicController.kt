package crm.desk

import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.validation.Valid
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.ModelAttribute
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestPart
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.multipart.MultipartFile

/**
 * The public report form (ADR-0007): no sign-in. It can read the catalog and the names of people, and create a
 * ticket - nothing else. Writes still need the CSRF cookie and header like every other write.
 */
@Tag(name = "Public desk")
@RestController
@RequestMapping("/api/public/desk")
class DeskPublicController(
    private val desk: DeskRepository,
    private val attachments: DeskAttachments,
    private val limiter: PublicReportLimiter,
) {

    @Operation(summary = "Categories, subcategories and priorities for the public form.")
    @GetMapping("/catalog")
    fun getPublicDeskCatalog(): DeskCatalog = desk.catalog()

    @Operation(summary = "People to pick the requester from: names and departments only.")
    @GetMapping("/people")
    fun listPublicPeople(): List<PublicPerson> = desk.publicPeople()

    @Operation(
        summary = "Report a ticket (reported now, into the pool) with optional files, in one transaction. " +
            "429 when too many were sent this minute.",
    )
    @PostMapping("/tickets", consumes = [MediaType.MULTIPART_FORM_DATA_VALUE])
    @ResponseStatus(HttpStatus.CREATED)
    fun reportPublicTicket(
        @Valid @ModelAttribute body: PublicReportRequest,
        @RequestPart("files", required = false) files: List<MultipartFile>?,
    ): PublicReportResponse {
        if (!limiter.tryAcquire()) throw TooManyPublicReportsException()
        return attachments.reportPublic(body, files.orEmpty())
    }
}
