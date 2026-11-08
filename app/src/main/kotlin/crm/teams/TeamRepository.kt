package crm.teams

import crm.shared.getLocalDateTime
import jakarta.validation.constraints.Size
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository
import java.math.BigDecimal
import java.sql.Types
import java.time.LocalDateTime

/** Teams. Every method is one `EXEC app.<procedure>`. */
@Repository
class TeamRepository(private val jdbc: JdbcClient) {

    private val teamRow = RowMapper { rs, _ ->
        TeamResponse(
            id = rs.getInt("id"),
            name = rs.getString("name"),
            leadUserId = rs.getInt("lead_user_id"),
            leadLogin = rs.getString("lead_login"),
            memberCount = rs.getInt("member_count"),
            createdAt = rs.getLocalDateTime("created_at"),
        )
    }

    fun list(actorId: Int, afterId: Int?, pageSize: Int): List<TeamResponse> =
        jdbc.sql("EXEC app.team_list @actor_id = :actorId, @after_id = :afterId, @page_size = :pageSize")
            .param("actorId", actorId, Types.INTEGER)
            .param("afterId", afterId, Types.INTEGER)
            .param("pageSize", pageSize, Types.INTEGER)
            .query(teamRow)
            .list()

    fun create(actorId: Int, name: String, leadUserId: Int): TeamResponse =
        jdbc.sql("EXEC app.team_create @actor_id = :actorId, @name = :name, @lead_user_id = :leadUserId")
            .param("actorId", actorId, Types.INTEGER)
            .param("name", name, Types.NVARCHAR)
            .param("leadUserId", leadUserId, Types.INTEGER)
            .query(teamRow)
            .single()

    fun members(actorId: Int, teamId: Int): List<TeamMemberResponse> =
        jdbc.sql("EXEC app.team_member_list @actor_id = :actorId, @team_id = :teamId")
            .param("actorId", actorId, Types.INTEGER)
            .param("teamId", teamId, Types.INTEGER)
            .query { rs, _ ->
                TeamMemberResponse(
                    userId = rs.getInt("user_id"),
                    login = rs.getString("login"),
                    displayName = rs.getString("display_name"),
                    role = rs.getString("role"),
                    active = rs.getBoolean("is_active"),
                    joinedAt = rs.getLocalDateTime("joined_at"),
                )
            }
            .list()

    fun addMember(actorId: Int, teamId: Int, userId: Int) {
        jdbc.sql("EXEC app.team_member_add @actor_id = :actorId, @team_id = :teamId, @user_id = :userId")
            .param("actorId", actorId, Types.INTEGER)
            .param("teamId", teamId, Types.INTEGER)
            .param("userId", userId, Types.INTEGER)
            .update()
    }

    fun removeMember(actorId: Int, teamId: Int, userId: Int) {
        jdbc.sql("EXEC app.team_member_remove @actor_id = :actorId, @team_id = :teamId, @user_id = :userId")
            .param("actorId", actorId, Types.INTEGER)
            .param("teamId", teamId, Types.INTEGER)
            .param("userId", userId, Types.INTEGER)
            .update()
    }

    fun projectStats(actorId: Int, teamId: Int): List<TeamStageStats> =
        jdbc.sql("EXEC app.team_project_stats @actor_id = :actorId, @team_id = :teamId")
            .param("actorId", actorId, Types.INTEGER)
            .param("teamId", teamId, Types.INTEGER)
            .query { rs, _ ->
                TeamStageStats(rs.getString("stage"), rs.getLong("project_count"), rs.getBigDecimal("budget_total"))
            }
            .list()
}
