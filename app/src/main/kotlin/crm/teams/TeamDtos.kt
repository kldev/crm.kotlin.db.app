package crm.teams

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Size
import java.math.BigDecimal
import java.time.LocalDateTime

data class TeamResponse(
    val id: Int,
    val name: String,
    val leadUserId: Int,
    val leadLogin: String,
    val memberCount: Int,
    val createdAt: LocalDateTime,
)

data class TeamMemberResponse(
    val userId: Int,
    val login: String,
    val displayName: String,
    val role: String,
    val active: Boolean,
    val joinedAt: LocalDateTime,
)

data class TeamStageStats(val stage: String, val projectCount: Long, val budgetTotal: BigDecimal)

data class CreateTeamRequest(
    @field:NotBlank @field:Size(max = 200) val name: String?,
    @field:NotNull val leadUserId: Int?,
)

data class AddMemberRequest(@field:NotNull val userId: Int?)
