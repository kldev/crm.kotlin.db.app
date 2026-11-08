package crm.projects

import crm.shared.RowVersion
import jakarta.validation.constraints.DecimalMin
import jakarta.validation.constraints.Digits
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import java.math.BigDecimal
import java.time.LocalDate
import java.time.LocalDateTime

const val STAGES = "NEW|ACCEPTED|ACTIVE|ON_HOLD|CLOSED|DECLINED"

/** One row of crm.v_projects. */
data class ProjectResponse(
    val id: Long,
    val name: String,
    val stage: String,
    val startDate: LocalDate,
    val dueDate: LocalDate,
    val budget: BigDecimal,
    val overdue: Boolean,
    val stageChangedAt: LocalDateTime,
    val clientId: Long,
    val clientName: String,
    val clientCity: String?,
    val teamId: Int,
    val teamName: String,
    val ownerUserId: Int,
    val ownerLogin: String,
    val ownerDisplayName: String,
    val updatedAt: LocalDateTime,
    val rowVersion: String,
)

data class CreateProjectRequest(
    @field:NotNull val clientId: Long?,
    @field:NotNull val teamId: Int?,
    @field:NotNull val ownerUserId: Int?,
    @field:NotBlank @field:Size(max = 200) val name: String?,
    @field:NotNull val startDate: LocalDate?,
    @field:NotNull val dueDate: LocalDate?,
    @field:NotNull @field:DecimalMin("0") @field:Digits(integer = 17, fraction = 2) val budget: BigDecimal?,
)

data class UpdateProjectRequest(
    @field:NotNull val teamId: Int?,
    @field:NotNull val ownerUserId: Int?,
    @field:NotBlank @field:Size(max = 200) val name: String?,
    @field:NotNull val startDate: LocalDate?,
    @field:NotNull val dueDate: LocalDate?,
    @field:NotNull @field:DecimalMin("0") @field:Digits(integer = 17, fraction = 2) val budget: BigDecimal?,
    @field:NotBlank @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

data class ChangeStageRequest(
    @field:NotBlank @field:Pattern(regexp = STAGES) val stage: String?,
    @field:Size(max = 4000) val comment: String?,
    @field:NotBlank @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

data class StageHistoryEntry(
    val id: Long,
    val fromStage: String?,
    val toStage: String,
    val changedAt: LocalDateTime,
    val changedBy: Int?,
    val changedByLogin: String?,
)

data class CommentResponse(
    val id: Long,
    val projectId: Long,
    val authorId: Int,
    val authorLogin: String,
    val authorDisplayName: String,
    val body: String,
    val createdAt: LocalDateTime,
)

data class AddCommentRequest(@field:NotBlank @field:Size(max = 4000) val body: String?)
