package crm.auth

import crm.shared.getLocalDateTimeOrNull
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository
import java.sql.Types

/** Procedures used by login. Every method is one `EXEC app.<procedure>`. */
@Repository
class AuthRepository(private val jdbc: JdbcClient) {

    fun findForLogin(login: String): CrmUserDetails? =
        jdbc.sql("EXEC app.user_get_for_login @login = :login")
            .param("login", login, Types.VARCHAR)
            .query { rs, _ ->
                CrmUserDetails(
                    id = rs.getInt("id"),
                    login = rs.getString("login"),
                    displayName = rs.getString("display_name"),
                    role = rs.getString("role"),
                    passwordHash = rs.getString("password_hash"),
                    active = rs.getBoolean("is_active"),
                    lockedUntil = rs.getLocalDateTimeOrNull("locked_until"),
                )
            }
            .optional()
            .orElse(null)

    fun loginSucceeded(userId: Int) {
        jdbc.sql("EXEC app.user_login_succeeded @user_id = :userId")
            .param("userId", userId, Types.INTEGER)
            .update()
    }

    fun loginFailed(login: String, maxFailed: Int, lockMinutes: Int) {
        jdbc.sql("EXEC app.user_login_failed @login = :login, @max_failed = :maxFailed, @lock_minutes = :lockMinutes")
            .param("login", login, Types.VARCHAR)
            .param("maxFailed", maxFailed, Types.INTEGER)
            .param("lockMinutes", lockMinutes, Types.INTEGER)
            .update()
    }

    fun setPassword(actorId: Int, userId: Int, passwordHash: String) {
        jdbc.sql("EXEC app.user_set_password @actor_id = :actorId, @id = :id, @password_hash = :hash")
            .param("actorId", actorId, Types.INTEGER)
            .param("id", userId, Types.INTEGER)
            .param("hash", passwordHash, Types.VARCHAR)
            .update()
    }

    /** Returns true when the administrator was created now. */
    fun ensureAdmin(login: String, passwordHash: String): Boolean =
        jdbc.sql("EXEC app.user_ensure_admin @login = :login, @display_name = :displayName, @password_hash = :hash")
            .param("login", login, Types.VARCHAR)
            .param("displayName", "Administrator", Types.NVARCHAR)
            .param("hash", passwordHash, Types.VARCHAR)
            .query { rs, _ -> rs.getBoolean("created") }
            .single()
}
