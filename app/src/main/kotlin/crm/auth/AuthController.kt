package crm.auth

import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.Parameter
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import jakarta.validation.Valid
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size
import org.springframework.http.HttpStatus
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
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.server.ResponseStatusException

data class LoginRequest(
    @field:NotBlank @field:Size(max = 64) val login: String?,
    @field:NotBlank @field:Size(max = 200) val password: String?,
)

data class ChangePasswordRequest(
    @field:NotBlank val currentPassword: String?,
    @field:NotBlank @field:Size(min = 8, max = 200) val newPassword: String?,
)

data class DevLoginRequest(@field:NotBlank @field:Size(max = 64) val login: String?)

data class DevLoginStatus(val enabled: Boolean)

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
    @Operation(summary = "Sets the XSRF-TOKEN cookie. Send its value as the X-XSRF-TOKEN header with every write request.")
    @GetMapping("/csrf")
    fun getCsrfToken(@Parameter(hidden = true) token: CsrfToken): ResponseEntity<Void> {
        token.token // loading the deferred token writes the cookie
        return ResponseEntity.noContent().build()
    }

    @Operation(summary = "Log in with login and password; starts a session (cookie). 401 for any failure.")
    @PostMapping("/login")
    fun login(
        @Valid @RequestBody body: LoginRequest,
        request: HttpServletRequest,
        response: HttpServletResponse,
    ): MeResponse {
        val login = body.login!!.trim().lowercase()
        val authentication = try {
            authenticationManager.authenticate(UsernamePasswordAuthenticationToken.unauthenticated(login, body.password))
        } catch (error: AuthenticationException) {
            if (error is BadCredentialsException) {
                auth.loginFailed(login, properties.maxFailedLogins, properties.lockMinutes)
            }
            // The same answer for an unknown login, a wrong password, a locked or a deactivated account.
            throw InvalidLoginException()
        }

        val user = (authentication.principal as CrmUserDetails).withoutPassword()
        auth.loginSucceeded(user.id)
        return startSession(user, request, response)
    }

    @Operation(summary = "Whether one-click development login is on (CRM_DEV_LOGIN). The login page shows it only then.")
    @GetMapping("/dev-login")
    fun getDevLoginStatus(): DevLoginStatus = DevLoginStatus(properties.devLogin)

    @Operation(
        summary = "Local development only (CRM_DEV_LOGIN=true, otherwise 404): log in as an active user without " +
            "a password. Skips the password and the lockout, nothing else; roles apply as usual.",
    )
    @PostMapping("/dev-login")
    fun devLogin(
        @Valid @RequestBody body: DevLoginRequest,
        request: HttpServletRequest,
        response: HttpServletResponse,
    ): MeResponse {
        if (!properties.devLogin) throw ResponseStatusException(HttpStatus.NOT_FOUND)
        val user = auth.findForLogin(body.login!!.trim().lowercase())
            ?.takeIf { it.isEnabled }
            ?.withoutPassword()
            ?: throw InvalidLoginException()
        return startSession(user, request, response)
    }

    private fun startSession(user: CrmUserDetails, request: HttpServletRequest, response: HttpServletResponse): MeResponse {
        // Session fixation protection: the session id changes on login.
        request.getSession(true)
        request.changeSessionId()
        val context = SecurityContextHolder.getContextHolderStrategy().createEmptyContext()
        context.authentication = UsernamePasswordAuthenticationToken.authenticated(user, null, user.authorities)
        SecurityContextHolder.getContextHolderStrategy().context = context
        contextRepository.saveContext(context, request, response)
        return MeResponse.from(user)
    }

    @Operation(summary = "The logged-in user.")
    @GetMapping("/me")
    fun getMe(@AuthenticationPrincipal user: CrmUserDetails): MeResponse = MeResponse.from(user)

    @Operation(summary = "Change own password (requires the current one).")
    @PostMapping("/password")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun changeOwnPassword(
        @AuthenticationPrincipal user: CrmUserDetails,
        @Valid @RequestBody body: ChangePasswordRequest,
    ) {
        val current = auth.findForLogin(user.login)
        if (current == null || !passwordEncoder.matches(body.currentPassword, current.password)) {
            throw WrongCurrentPasswordException()
        }
        auth.setPassword(user.id, user.id, passwordEncoder.encode(body.newPassword!!)!!)
    }
}

/** 401 "Invalid login or password." - one answer for every login failure. */
class InvalidLoginException : RuntimeException("Invalid login or password.")

/** 400 when the current password given to change it is wrong. */
class WrongCurrentPasswordException : RuntimeException("Current password is not correct.")
