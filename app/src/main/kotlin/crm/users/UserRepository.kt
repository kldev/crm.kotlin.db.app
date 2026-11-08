package crm.users

import crm.shared.getLocalDateTime
import crm.shared.getLocalDateTimeOrNull
import crm.shared.getRowVersion
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository
import java.sql.Types

/** User administration. Every method is one `EXEC app.<procedure>`. */
@Repository
class UserRepository(private val jdbc: JdbcClient) {

    private val userRow = RowMapper { rs, _ ->
        UserResponse(
            id = rs.getInt("id"),
            login = rs.getString("login"),
            displayName = rs.getString("display_name"),
            role = rs.getString("role"),
            active = rs.getBoolean("is_active"),
            lockedUntil = rs.getLocalDateTimeOrNull("locked_until"),
            lastLoginAt = rs.getLocalDateTimeOrNull("last_login_at"),
            createdAt = rs.getLocalDateTime("created_at"),
            updatedAt = rs.getLocalDateTime("updated_at"),
            rowVersion = rs.getRowVersion(),
        )
    }

    fun list(actorId: Int, role: String?, afterId: Int?, pageSize: Int): List<UserResponse> =
        jdbc.sql(
            "EXEC app.user_list @actor_id = :actorId, @role = :role, @after_id = :afterId, @page_size = :pageSize",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("role", role, Types.VARCHAR)
            .param("afterId", afterId, Types.INTEGER)
            .param("pageSize", pageSize, Types.INTEGER)
            .query(userRow)
            .list()

    fun create(actorId: Int, login: String, displayName: String, role: String, passwordHash: String): UserResponse =
        jdbc.sql(
            "EXEC app.user_create @actor_id = :actorId, @login = :login, @display_name = :displayName, " +
                "@role = :role, @password_hash = :hash",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("login", login, Types.VARCHAR)
            .param("displayName", displayName, Types.NVARCHAR)
            .param("role", role, Types.VARCHAR)
            .param("hash", passwordHash, Types.VARCHAR)
            .query(userRow)
            .single()

    fun changeRole(actorId: Int, id: Int, role: String): UserResponse =
        jdbc.sql("EXEC app.user_change_role @actor_id = :actorId, @id = :id, @role = :role")
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.INTEGER)
            .param("role", role, Types.VARCHAR)
            .query(userRow)
            .single()

    fun setActive(actorId: Int, id: Int, active: Boolean): UserResponse =
        jdbc.sql("EXEC app.user_set_active @actor_id = :actorId, @id = :id, @is_active = :active")
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.INTEGER)
            .param("active", active, Types.BIT)
            .query(userRow)
            .single()

    fun setPassword(actorId: Int, id: Int, passwordHash: String) {
        jdbc.sql("EXEC app.user_set_password @actor_id = :actorId, @id = :id, @password_hash = :hash")
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.INTEGER)
            .param("hash", passwordHash, Types.VARCHAR)
            .update()
    }
}
