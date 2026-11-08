package crm.desk

import crm.auth.CrmUserDetails
import crm.shared.Cursor
import crm.shared.InvalidCursorException
import crm.shared.PageResponse
import crm.shared.TotalResponse
import crm.storage.AttachmentStorage
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.validation.Valid
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import org.springframework.http.ContentDisposition
import org.springframework.http.HttpHeaders
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RequestPart
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.multipart.MultipartFile
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.time.format.DateTimeParseException
import java.util.UUID

/**
 * The service desk for agents (ADR-0007): every active CRM user is an agent and sees every ticket.
 * Each action appends one event to the ticket's stream; the procedures decide whether it is allowed.
 */
@Tag(name = "Desk")
@RestController
@RequestMapping("/api/desk")
class DeskController(
    private val desk: DeskRepository,
    private val attachments: DeskAttachments,
    private val storage: AttachmentStorage,
) {

    @Operation(summary = "Categories, subcategories and priorities with their SLA.")
    @GetMapping("/catalog")
    fun getDeskCatalog(): DeskCatalog = desk.catalog()

    @Operation(
        summary = "Tickets page. scope POOL / MINE / ALL; open tickets by deadline first, then resolved ones, " +
            "newest first.",
    )
    @GetMapping("/tickets")
    fun searchTickets(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(defaultValue = "ALL") scope: String,
        @RequestParam(required = false) categoryKey: String?,
        @RequestParam(required = false) subcategoryKey: String?,
        @RequestParam(required = false) priority: String?,
        @RequestParam(required = false) deadline: String?,
        @RequestParam(required = false) completion: String?,
        @RequestParam(required = false) search: String?,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "25") @Min(1) @Max(200) size: Int,
    ): PageResponse<TicketResponse> {
        val filter = TicketFilter(scope, categoryKey, subcategoryKey, priority, deadline, completion, search)
        val after = Cursor.decode(cursor, 3)?.let { parts ->
            try {
                TicketKey(parts[0].toInt(), Instant.parse(parts[1]), parts[2].toLong())
            } catch (_: NumberFormatException) {
                throw InvalidCursorException("Invalid cursor.")
            } catch (_: DateTimeParseException) {
                throw InvalidCursorException("Invalid cursor.")
            }
        }
        val rows = desk.search(actor.id, filter, after, size)
        return Cursor.page(rows, size) {
            if (it.status == "DONE") Cursor.encode(1, it.resolvedAt, it.id) else Cursor.encode(0, it.deadline, it.id)
        }
    }

    @Operation(summary = "Number of tickets matching the same filters as the list. Call it only on request.")
    @GetMapping("/tickets/count")
    fun countTickets(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(defaultValue = "ALL") scope: String,
        @RequestParam(required = false) categoryKey: String?,
        @RequestParam(required = false) subcategoryKey: String?,
        @RequestParam(required = false) priority: String?,
        @RequestParam(required = false) deadline: String?,
        @RequestParam(required = false) completion: String?,
        @RequestParam(required = false) search: String?,
    ): TotalResponse = TotalResponse(
        desk.count(actor.id, TicketFilter(scope, categoryKey, subcategoryKey, priority, deadline, completion, search)),
    )

    @Operation(summary = "Counters of the top bar: overdue, due soon, in the pool, mine.")
    @GetMapping("/tickets/counters")
    fun getTicketCounters(@AuthenticationPrincipal actor: CrmUserDetails): TicketCounters = desk.counters(actor.id)

    @Operation(summary = "Register a ticket for a requester (a call, an e-mail); may be dated back up to 30 days.")
    @PostMapping("/tickets")
    @ResponseStatus(HttpStatus.CREATED)
    fun reportTicket(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @Valid @RequestBody body: ReportTicketRequest,
    ): TicketResponse = desk.report(actor.id, body)

    @Operation(summary = "Ticket details.")
    @GetMapping("/tickets/{id}")
    fun getTicket(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Long): TicketResponse =
        desk.get(actor.id, id)

    @Operation(summary = "Ticket by its public number (HAL-XXXXXXXX).")
    @GetMapping("/tickets/by-number/{number}")
    fun findTicket(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable number: String): TicketResponse =
        desk.find(actor.id, number)

    @Operation(summary = "The ticket's events, oldest first: its timeline.")
    @GetMapping("/tickets/{id}/events")
    fun listTicketEvents(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Long): List<TicketEventResponse> =
        desk.events(actor.id, id)

    @Operation(summary = "Take a ticket from the pool. 409 when someone was faster.")
    @PostMapping("/tickets/{id}/take")
    fun takeTicket(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Long): TicketResponse =
        desk.take(actor.id, id)

    @Operation(summary = "Hand the ticket over to another agent (only the agent working on it).")
    @PostMapping("/tickets/{id}/hand-over")
    fun handOverTicket(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: HandOverRequest,
    ): TicketResponse = desk.handOver(actor.id, id, body)

    @Operation(summary = "Give the ticket back to the pool (only the agent working on it).")
    @PostMapping("/tickets/{id}/return")
    fun returnTicket(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: ReasonRequest,
    ): TicketResponse = desk.returnToPool(actor.id, id, body)

    @Operation(summary = "Change the priority; the deadline is recomputed from the report date.")
    @PostMapping("/tickets/{id}/priority")
    fun changeTicketPriority(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: ChangePriorityRequest,
    ): TicketResponse = desk.changePriority(actor.id, id, body)

    @Operation(summary = "Resolve the ticket (only the agent working on it).")
    @PostMapping("/tickets/{id}/resolve")
    fun resolveTicket(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Long): TicketResponse =
        desk.resolve(actor.id, id)

    @Operation(summary = "Add a comment (any state).")
    @PostMapping("/tickets/{id}/comments")
    fun commentTicket(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: CommentRequest,
    ): TicketResponse = desk.comment(actor.id, id, body)

    @Operation(summary = "Name the person who does the work, or take them off (only the agent working on it).")
    @PostMapping("/tickets/{id}/handler")
    fun assignTicketHandler(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: AssignHandlerRequest,
    ): TicketResponse = desk.assignHandler(actor.id, id, body)

    @Operation(summary = "The ticket's attachments, oldest first.")
    @GetMapping("/tickets/{id}/attachments")
    fun listTicketAttachments(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
    ): List<AttachmentResponse> = desk.attachments(actor.id, id)

    @Operation(
        summary = "Attach files (any state): at most 10 per ticket, 20 MB each, images, PDF, Office, TXT/CSV, ZIP, " +
            "MP4/MOV - never SVG or HTML.",
    )
    @PostMapping("/tickets/{id}/attachments", consumes = [MediaType.MULTIPART_FORM_DATA_VALUE])
    fun attachTicketFiles(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @RequestPart("files") files: List<MultipartFile>,
    ): TicketResponse = attachments.attach(actor.id, id, files)

    @Operation(
        summary = "Download an attachment. Images and PDF inline (or with download=true as a file), the rest as a file; " +
            "always nosniff and a sandbox CSP.",
    )
    @GetMapping("/tickets/{id}/attachments/{attachmentId}")
    fun downloadTicketAttachment(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @PathVariable attachmentId: UUID,
        @RequestParam(defaultValue = "false") download: Boolean,
    ): ResponseEntity<StreamingResponseBody> {
        val file = desk.attachment(actor.id, id, attachmentId)
        val disposition = (if (file.inline && !download) ContentDisposition.inline() else ContentDisposition.attachment())
            .filename(file.fileName, StandardCharsets.UTF_8)
            .build()
        val body = StreamingResponseBody { out -> storage.open(file.storageKey).use { it.transferTo(out) } }
        return ResponseEntity.ok()
            .contentType(MediaType.parseMediaType(file.contentType))
            .contentLength(file.size)
            .header(HttpHeaders.CONTENT_DISPOSITION, disposition.toString())
            // The type is the one the extension allows; the browser must not guess another, nor run anything.
            .header("X-Content-Type-Options", "nosniff")
            .header("Content-Security-Policy", "sandbox")
            .header(HttpHeaders.CACHE_CONTROL, "private, max-age=3600")
            .body(body)
    }

    @Operation(summary = "Agents (active CRM users) with their tickets in progress; by name, `search` = name prefix.")
    @GetMapping("/agents")
    fun listDeskAgents(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(required = false) search: String?,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "50") @Min(1) @Max(200) size: Int,
    ): PageResponse<AgentSummary> {
        val parts = Cursor.decode(cursor, 2)
        val afterId = parts?.let { it[0].toIntOrNull() ?: throw InvalidCursorException("Invalid cursor.") }
        val rows = desk.agents(actor.id, search, parts?.get(1), afterId, size)
        return Cursor.page(rows, size) { Cursor.encode(it.id, it.displayName) }
    }

    @Operation(summary = "People (requesters and handlers) with their contacts.")
    @GetMapping("/people")
    fun listDeskPeople(@AuthenticationPrincipal actor: CrmUserDetails): List<PersonResponse> = desk.people(actor.id)
}
