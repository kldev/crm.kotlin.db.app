package crm.desk

import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.validation.Valid
import org.springframework.http.HttpStatus
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController

/**
 * The public report form (ADR-0007): no sign-in. It can read the catalog and the names of people, and create a
 * ticket - nothing else. Writes still need the CSRF cookie and header like every other write.
 */
@Tag(name = "Public desk")
@RestController
@RequestMapping("/api/public/desk")
class DeskPublicController(private val desk: DeskRepository, private val limiter: PublicReportLimiter) {

    @Operation(summary = "Categories, subcategories and priorities for the public form.")
    @GetMapping("/catalog")
    fun getPublicDeskCatalog(): DeskCatalog = desk.catalog()

    @Operation(summary = "People to pick the requester from: names and departments only.")
    @GetMapping("/people")
    fun listPublicPeople(): List<PublicPerson> = desk.publicPeople()

    @Operation(summary = "Report a ticket (reported now, into the pool). 429 when too many were sent this minute.")
    @PostMapping("/tickets")
    @ResponseStatus(HttpStatus.CREATED)
    fun reportPublicTicket(@Valid @RequestBody body: PublicReportRequest): PublicReportResponse {
        if (!limiter.tryAcquire()) throw TooManyPublicReportsException()
        return desk.reportPublic(body)
    }
}
