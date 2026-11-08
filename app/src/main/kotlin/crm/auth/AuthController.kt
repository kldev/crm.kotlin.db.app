package crm.auth

import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import jakarta.validation.Valid
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size
import org.springframework.http.HttpStatus
import org.springframework.http.ProblemDetail
import org.springframework.http.ResponseEntity
import org.springframework.security.authentication.AuthenticationManager
import org.springframework.security.authentication.BadCredentialsException
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken
import org.springframework.security.core.AuthenticationException
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.security.web.context.SecurityContextRepository
import org.springframework.security.web.csrf.CsrfToken
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

data class LoginRequest(
    @field:NotBlank @field:Size(max = 64) val login: String?,
    @field:NotBlank @field:Size(max = 200) val password: String?,
)

data class ChangePasswordRequest(
    @field:NotBlank val currentPassword: String?,
    @field:NotBlank @field:Size(min = 8, max = 200) val newPassword: String?,
)

data class MeResponse(val id: Int, val login: String, val displayName: String, val role: String) {
    companion object {
        fun from(user: CrmUserDetails) = MeResponse(user.id, user.login, user.displayName, user.role)
    }
}

@Tag(name = "Auth")
@RestController
@RequestMapping("/api/auth")
class AuthController(
    private val authenticationManager: AuthenticationManager,
    private val contextRepository: SecurityContextRepository,
    private val auth: AuthRepository,
    private val passwordEncoder: PasswordEncoder,
    private val properties: AuthProperties,
) {
    @Operation(summary = "Sets the XSRF-TOKEN cookie. Send its value as the X-XSRF-TOKEN header on POST/PUT/DELETE.")
    @GetMapping("/csrf")
    fun csrf(token: CsrfToken): ResponseEntity<Void> {
        token.token // loading the deferred token writes the cookie
        return ResponseEntity.noContent().build()
    }

    @Operation(summary = "Log in with login and password; starts a session (cookie).")
    @PostMapping("/login")
    fun login(
        @Valid @RequestBody body: LoginRequest,
        request: HttpServletRequest,
        response: HttpServletResponse,
    ): ResponseEntity<Any> {
        val login = body.login!!.trim().lowercase()
        val authentication = try {
            authenticationManager.authenticate(UsernamePasswordAuthenticationToken.unauthenticated(login, body.password))
        } catch (error: AuthenticationException) {
            if (error is BadCredentialsException) {
                auth.loginFailed(login, properties.maxFailedLogins, properties.lockMinutes)
            }
            // The same answer for an unknown login, a wrong password, a locked or a deactivated account.
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(ProblemDetail.forStatusAndDetail(HttpStatus.UNAUTHORIZED, "Invalid login or password."))
        }

        val user = (authentication.principal as CrmUserDetails).withoutPassword()
        auth.loginSucceeded(user.id)

        // Session fixation protection: the session id changes on login.
        request.getSession(true)
        request.changeSessionId()
        val context = SecurityContextHolder.getContextHolderStrategy().createEmptyContext()
        context.authentication = UsernamePasswordAuthenticationToken.authenticated(user, null, user.authorities)
        SecurityContextHolder.getContextHolderStrategy().context = context
        contextRepository.saveContext(context, request, response)

        return ResponseEntity.ok(MeResponse.from(user))
    }

    @Operation(summary = "The logged-in user.")
    @GetMapping("/me")
    fun me(@AuthenticationPrincipal user: CrmUserDetails): MeResponse = MeResponse.from(user)

    @Operation(summary = "Change own password (requires the current one).")
    @PostMapping("/password")
    fun changePassword(
        @AuthenticationPrincipal user: CrmUserDetails,
        @Valid @RequestBody body: ChangePasswordRequest,
    ): ResponseEntity<Any> {
        val current = auth.findForLogin(user.login)
        if (current == null || !passwordEncoder.matches(body.currentPassword, current.password)) {
            return ResponseEntity.badRequest()
                .body(ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, "Current password is not correct."))
        }
        auth.setPassword(user.id, user.id, passwordEncoder.encode(body.newPassword!!)!!)
        return ResponseEntity.noContent().build()
    }
}
