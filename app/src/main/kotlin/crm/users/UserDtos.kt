package crm.users

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import java.time.LocalDateTime

data class UserResponse(
    val id: Int,
    val login: String,
    val displayName: String,
    val role: String,
    val active: Boolean,
    val lockedUntil: LocalDateTime?,
    val lastLoginAt: LocalDateTime?,
    val createdAt: LocalDateTime,
    val updatedAt: LocalDateTime,
    val rowVersion: String,
    /** For the "my department" views of tasks (ADR-0014); set by an administrator. */
    val department: String?,
)

data class CreateUserRequest(
    @field:NotBlank @field:Size(min = 3, max = 64) val login: String?,
    @field:NotBlank @field:Size(max = 200) val displayName: String?,
    @field:NotBlank @field:Pattern(regexp = "ADMIN|MANAGER|SALES") val role: String?,
    @field:NotBlank @field:Size(min = 8, max = 200) val password: String?,
)

data class ChangeRoleRequest(
    @field:NotBlank @field:Pattern(regexp = "ADMIN|MANAGER|SALES") val role: String?,
)

data class SetActiveRequest(@field:NotNull val active: Boolean?)

data class ResetPasswordRequest(@field:NotBlank @field:Size(min = 8, max = 200) val password: String?)
