package crm.auth

import org.springframework.boot.context.properties.ConfigurationProperties
import org.springframework.validation.annotation.Validated
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min

/**
 * Login and lockout settings (env only, never UI): CRM_LOGIN_MAX_FAILED, CRM_LOGIN_LOCK_MINUTES.
 * The first administrator: CRM_ADMIN_LOGIN / CRM_ADMIN_PASSWORD, created only when there is no ADMIN yet.
 * CRM_DEV_LOGIN=true: one-click login as any active user without a password (local development only, off by default).
 */
@Validated
@ConfigurationProperties("crm.auth")
data class AuthProperties(
    @field:Min(1) @field:Max(100) val maxFailedLogins: Int = 5,
    @field:Min(1) @field:Max(1440) val lockMinutes: Int = 15,
    val adminLogin: String? = null,
    val adminPassword: String? = null,
    val devLogin: Boolean = false,
)
