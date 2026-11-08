package crm.projects

import crm.auth.CrmUserDetails
import crm.shared.Cursor
import crm.shared.InvalidCursorException
import crm.shared.PageResponse
import crm.shared.TotalResponse
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.validation.Valid
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import org.springframework.format.annotation.DateTimeFormat
import org.springframework.http.HttpStatus
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.time.LocalDate
import java.time.format.DateTimeParseException

@Tag(name = "Projects")
@RestController
@RequestMapping("/api/projects")
class ProjectController(private val projects: ProjectRepository) {

    @Operation(
        summary = "Projects page ordered by due date. SALES users see own projects, projects of their teams " +
            "and projects of their clients.",
    )
    @GetMapping
    fun searchProjects(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(required = false) stage: String?,
        @RequestParam(required = false) teamId: Int?,
        @RequestParam(required = false) clientId: Long?,
        @RequestParam(required = false) ownerUserId: Int?,
        @RequestParam(defaultValue = "false") overdue: Boolean,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) dueFrom: LocalDate?,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) dueTo: LocalDate?,
        @RequestParam(required = false) legalEntityId: Int?,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "50") @Min(1) @Max(200) size: Int,
    ): PageResponse<ProjectResponse> {
        val parts = Cursor.decode(cursor, 2)
        val (afterDueDate, afterId) = try {
            parts?.let { LocalDate.parse(it[0]) to it[1].toLong() } ?: (null to null)
        } catch (_: DateTimeParseException) {
            throw InvalidCursorException("Invalid cursor.")
        } catch (_: NumberFormatException) {
            throw InvalidCursorException("Invalid cursor.")
        }
        val filter = ProjectFilter(stage, teamId, clientId, ownerUserId, overdue, dueFrom, dueTo, legalEntityId)
        val rows = projects.search(actor.id, filter, afterDueDate, afterId, size)
        return Cursor.page(rows, size) { Cursor.encode(it.dueDate, it.id) }
    }

    @Operation(
        summary = "Number of projects matching the same filters as the list. Reads every matching row, " +
            "so call it only when the user asks for the total.",
    )
    @GetMapping("/count")
    fun countProjects(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(required = false) stage: String?,
        @RequestParam(required = false) teamId: Int?,
        @RequestParam(required = false) clientId: Long?,
        @RequestParam(required = false) ownerUserId: Int?,
        @RequestParam(defaultValue = "false") overdue: Boolean,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) dueFrom: LocalDate?,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) dueTo: LocalDate?,
        @RequestParam(required = false) legalEntityId: Int?,
    ): TotalResponse =
        TotalResponse(projects.count(actor.id, ProjectFilter(stage, teamId, clientId, ownerUserId, overdue, dueFrom, dueTo, legalEntityId)))

    @Operation(summary = "Project details.")
    @GetMapping("/{id}")
    fun getProject(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Long): ProjectResponse =
        projects.get(actor.id, id)

    @Operation(summary = "Create a project (stage NEW). The owner must be a member of the team.")
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    fun createProject(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @Valid @RequestBody body: CreateProjectRequest,
    ): ProjectResponse = projects.create(actor.id, body)

    @Operation(summary = "Update project details (not the stage). `rowVersion` from the last read is required.")
    @PutMapping("/{id}")
    fun updateProject(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: UpdateProjectRequest,
    ): ProjectResponse = projects.update(actor.id, id, body)

    @Operation(
        summary = "Move the project to another stage, optionally with a comment. " +
            "Allowed: NEW->ACCEPTED|DECLINED, ACCEPTED->ACTIVE|DECLINED, ACTIVE->ON_HOLD|CLOSED, ON_HOLD->ACTIVE|CLOSED.",
    )
    @PostMapping("/{id}/stage")
    fun changeProjectStage(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: ChangeStageRequest,
    ): ProjectResponse = projects.changeStage(actor.id, id, body)

    @Operation(summary = "Stage history of the project, newest first.")
    @GetMapping("/{id}/stages")
    fun listProjectStages(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Long): List<StageHistoryEntry> =
        projects.stageHistory(actor.id, id)

    @Operation(summary = "Comments of the project, newest first.")
    @GetMapping("/{id}/comments")
    fun listProjectComments(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "50") @Min(1) @Max(200) size: Int,
    ): PageResponse<CommentResponse> {
        val beforeId = Cursor.decode(cursor, 1)?.let { it[0].toLongOrNull() ?: throw InvalidCursorException("Invalid cursor.") }
        val rows = projects.comments(actor.id, id, beforeId, size)
        return Cursor.page(rows, size) { Cursor.encode(it.id) }
    }

    @Operation(summary = "Add a comment to the project.")
    @PostMapping("/{id}/comments")
    @ResponseStatus(HttpStatus.CREATED)
    fun addProjectComment(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: AddCommentRequest,
    ): CommentResponse = projects.addComment(actor.id, id, body.body!!)
}
