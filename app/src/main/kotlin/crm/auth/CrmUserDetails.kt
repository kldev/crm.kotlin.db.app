package crm.auth

import org.springframework.security.core.GrantedAuthority
import org.springframework.security.core.authority.SimpleGrantedAuthority
import org.springframework.security.core.userdetails.UserDetails
import java.io.Serializable
import java.time.LocalDateTime
import java.time.ZoneOffset

/**
 * The logged-in user kept in the HTTP session. `id` is the actor passed to every procedure (@actor_id);
 * the procedures re-check the current role and active flag on each call.
 */
data class CrmUserDetails(
    val id: Int,
    val login: String,
    val displayName: String,
    val role: String,
    private val passwordHash: String?,
    private val active: Boolean,
    private val lockedUntil: LocalDateTime?,
) : UserDetails, Serializable {
    override fun getAuthorities(): Collection<GrantedAuthority> = listOf(SimpleGrantedAuthority("ROLE_$role"))

    override fun getPassword(): String? = passwordHash

    override fun getUsername(): String = login

    override fun isEnabled(): Boolean = active

    override fun isAccountNonLocked(): Boolean =
        lockedUntil == null || lockedUntil.isBefore(LocalDateTime.now(ZoneOffset.UTC))

    /** Copy without the password hash - this is what goes into the session. */
    fun withoutPassword(): CrmUserDetails = copy(passwordHash = null)
}
