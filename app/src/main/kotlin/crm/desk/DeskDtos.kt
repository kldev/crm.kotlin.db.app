package crm.desk

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import java.time.Instant
import java.util.UUID

const val PRIORITIES = "CRITICAL|HIGH|MEDIUM|LOW"

/** One row of crm.tickets, the read model of a ticket's stream (ADR-0007). Times are UTC instants. */
data class TicketResponse(
    val id: Long,
    val number: String,
    val title: String,
    val description: String,
    val categoryKey: String,
    val subcategoryKey: String,
    val priority: String,
    val originalPriority: String,
    val reportedAt: Instant,
    val deadline: Instant,
    /** IN_POOL, IN_PROGRESS or DONE. */
    val status: String,
    /** In progress: who works on it; resolved: who resolved it. */
    val assigneeUserId: Int?,
    val assigneeName: String?,
    val handlerPersonId: Int?,
    val handlerName: String?,
    val requesterIncognito: Boolean,
    val requesterPersonId: Int?,
    val requesterName: String?,
    /** AGENT or SELF_SERVICE. */
    val channel: String,
    val registeredByName: String?,
    val recordedAt: Instant,
    val resolvedAt: Instant?,
    val resolvedLate: Boolean,
    val commentCount: Int,
    val attachmentCount: Int,
    val version: Int,
    val lastChangeAt: Instant,
)

/** One event of a ticket's stream. `data` is the event's JSON; its shape depends on `type`. */
data class TicketEventResponse(
    val version: Int,
    val type: String,
    val at: Instant,
    val actorUserId: Int?,
    val actorName: String?,
    val data: String,
)

data class TicketCounters(val overdue: Int, val dueSoon: Int, val pool: Int, val mine: Int)

data class ReportTicketRequest(
    @field:NotBlank @field:Size(max = 200) val title: String?,
    @field:NotBlank @field:Size(max = 4000) val description: String?,
    @field:NotBlank val categoryKey: String?,
    @field:NotBlank val subcategoryKey: String?,
    @field:NotBlank @field:Pattern(regexp = PRIORITIES) val priority: String?,
    /** When the request was made (a call this morning); at most 30 days back. */
    @field:NotNull val reportedAt: Instant?,
    val requesterPersonId: Int?,
    val requesterIncognito: Boolean?,
)

data class PublicReportRequest(
    @field:NotBlank @field:Size(max = 200) val title: String?,
    @field:NotBlank @field:Size(max = 4000) val description: String?,
    @field:NotBlank val categoryKey: String?,
    @field:NotBlank val subcategoryKey: String?,
    @field:NotBlank @field:Pattern(regexp = PRIORITIES) val priority: String?,
    val requesterPersonId: Int?,
    val requesterIncognito: Boolean?,
)

/** What the public form tells the requester: the number to quote and the deadline. */
data class PublicReportResponse(val number: String, val deadline: Instant)

data class HandOverRequest(
    @field:NotNull val toUserId: Int?,
    @field:Size(max = 500) val reason: String?,
)

data class ReasonRequest(@field:Size(max = 500) val reason: String?)

data class ChangePriorityRequest(
    @field:NotBlank @field:Pattern(regexp = PRIORITIES) val priority: String?,
    @field:Size(max = 500) val reason: String?,
)

data class CommentRequest(@field:NotBlank @field:Size(max = 2000) val text: String?)

data class AssignHandlerRequest(
    /** Null takes the handler off. */
    val personId: Int?,
    @field:Size(max = 500) val reason: String?,
)

data class AgentSummary(
    val id: Int,
    val login: String,
    val displayName: String,
    val role: String,
    val inProgress: Int,
)

data class PersonResponse(
    val id: Int,
    val firstName: String,
    val lastName: String,
    val department: String,
    val email: String,
    val phone: String?,
)

/** A person as the public form shows them: no contacts. */
data class PublicPerson(val id: Int, val firstName: String, val lastName: String, val department: String)

data class SubcategoryResponse(val key: String, val name: String, val market: String?, val active: Boolean)

data class CategoryResponse(
    val key: String,
    val name: String,
    val department: String?,
    val subcategories: List<SubcategoryResponse>,
)

data class PriorityResponse(val priority: String, val slaMinutes: Int)

/**
 * Everything a form needs to offer: the catalog, the priorities with their SLA and the file extensions an attachment
 * may have (for the file picker's accept attribute).
 */
data class DeskCatalog(
    val categories: List<CategoryResponse>,
    val priorities: List<PriorityResponse>,
    val attachmentExtensions: List<String>,
)

data class AttachmentResponse(
    val id: UUID,
    val fileName: String,
    val contentType: String,
    val size: Long,
    val addedBy: String,
    val at: Instant,
    /** Images and PDF open in the browser; the rest is downloaded. */
    val inline: Boolean,
)

/** A file checked by the procedure: the name as stored and its type. */
data class CheckedFile(val fileName: String, val contentType: String)

/** A stored file the procedure records; serialised as the JSON the procedures read. */
data class StoredFile(val id: UUID, val fileName: String, val size: Long, val storageKey: String)

/** Where an attachment's bytes are and how to send them. */
data class AttachmentLocation(
    val fileName: String,
    val contentType: String,
    val size: Long,
    val storageKey: String,
    val inline: Boolean,
)
