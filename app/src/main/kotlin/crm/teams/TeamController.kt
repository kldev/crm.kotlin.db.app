package crm.teams

import crm.auth.CrmUserDetails
import crm.shared.Cursor
import crm.shared.InvalidCursorException
import crm.shared.PageResponse
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.validation.Valid
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import org.springframework.http.HttpStatus
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.stereotype.Repository
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController

@Tag(name = "Teams")
@RestController
@RequestMapping("/api/teams")
class TeamController(private val teams: TeamRepository) {

    @Operation(summary = "Teams page, ordered by id.")
    @GetMapping
    fun list(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "50") @Min(1) @Max(200) size: Int,
    ): PageResponse<TeamResponse> {
        val afterId = Cursor.decode(cursor, 1)?.let { it[0].toIntOrNull() ?: throw InvalidCursorException("Invalid cursor.") }
        return Cursor.page(teams.list(actor.id, afterId, size), size) { Cursor.encode(it.id) }
    }

    @Operation(summary = "Create a team led by an active manager (ADMIN).")
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    fun create(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @Valid @RequestBody body: CreateTeamRequest,
    ): TeamResponse = teams.create(actor.id, body.name!!, body.leadUserId!!)

    @Operation(summary = "Members of the team.")
    @GetMapping("/{id}/members")
    fun members(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Int): List<TeamMemberResponse> =
        teams.members(actor.id, id)

    @Operation(summary = "Add a member (ADMIN or the team lead).")
    @PostMapping("/{id}/members")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun addMember(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Int,
        @Valid @RequestBody body: AddMemberRequest,
    ) {
        teams.addMember(actor.id, id, body.userId!!)
    }

    @Operation(summary = "Remove a member (ADMIN or the team lead); not while they own open projects of the team.")
    @DeleteMapping("/{id}/members/{userId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun removeMember(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Int, @PathVariable userId: Int) {
        teams.removeMember(actor.id, id, userId)
    }

    @Operation(summary = "Projects and budget of the team per stage (indexed view).")
    @GetMapping("/{id}/stats")
    fun stats(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Int): List<TeamStageStats> =
        teams.projectStats(actor.id, id)
}
