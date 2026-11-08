package crm.users

import crm.auth.CrmUserDetails
import crm.shared.Cursor
import crm.shared.PageResponse
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.validation.Valid
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import org.springframework.http.HttpStatus
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController

/** User administration: ADMIN writes, ADMIN and MANAGER read (also enforced in the procedures). */
@Tag(name = "Users")
@RestController
@RequestMapping("/api/users")
class UserController(
    private val users: UserRepository,
    private val passwordEncoder: PasswordEncoder,
) {
    @Operation(summary = "Users page, ordered by id.")
    @GetMapping
    fun list(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(required = false) role: String?,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "50") @Min(1) @Max(200) size: Int,
    ): PageResponse<UserResponse> {
        val afterId = Cursor.decode(cursor, 1)?.let { it[0].toIntOrNull() }
        val rows = users.list(actor.id, role, afterId, size)
        return Cursor.page(rows, size) { Cursor.encode(it.id) }
    }

    @Operation(summary = "Create a user.")
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    fun create(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @Valid @RequestBody body: CreateUserRequest,
    ): UserResponse = users.create(
        actor.id,
        body.login!!,
        body.displayName!!,
        body.role!!,
        passwordEncoder.encode(body.password!!)!!,
    )

    @Operation(summary = "Change the role of a user (not your own).")
    @PutMapping("/{id}/role")
    fun changeRole(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Int,
        @Valid @RequestBody body: ChangeRoleRequest,
    ): UserResponse = users.changeRole(actor.id, id, body.role!!)

    @Operation(summary = "Activate or deactivate a user (not yourself).")
    @PutMapping("/{id}/active")
    fun setActive(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Int,
        @Valid @RequestBody body: SetActiveRequest,
    ): UserResponse = users.setActive(actor.id, id, body.active!!)

    @Operation(summary = "Set a new password for a user; clears a lockout.")
    @PutMapping("/{id}/password")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun resetPassword(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Int,
        @Valid @RequestBody body: ResetPasswordRequest,
    ) {
        users.setPassword(actor.id, id, passwordEncoder.encode(body.password!!)!!)
    }
}
