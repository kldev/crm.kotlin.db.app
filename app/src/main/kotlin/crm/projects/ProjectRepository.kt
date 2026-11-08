package crm.projects

import crm.shared.RowVersion
import crm.shared.getIntOrNull
import crm.shared.getLocalDate
import crm.shared.getLocalDateTime
import crm.shared.getRowVersion
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository
import java.sql.Types
import java.time.LocalDate

data class ProjectFilter(
    val stage: String?,
    val teamId: Int?,
    val clientId: Long?,
    val ownerUserId: Int?,
    val overdueOnly: Boolean,
    val dueFrom: LocalDate?,
    val dueTo: LocalDate?,
    val legalEntityId: Int? = null,
)

/** Projects, their stage history and comments. Every method is one `EXEC app.<procedure>`. */
@Repository
class ProjectRepository(private val jdbc: JdbcClient) {

    private val projectRow = RowMapper { rs, _ ->
        ProjectResponse(
            id = rs.getLong("id"),
            name = rs.getString("name"),
            stage = rs.getString("stage"),
            startDate = rs.getLocalDate("start_date"),
            dueDate = rs.getLocalDate("due_date"),
            budget = rs.getBigDecimal("budget"),
            overdue = rs.getBoolean("is_overdue"),
            stageChangedAt = rs.getLocalDateTime("stage_changed_at"),
            clientId = rs.getLong("client_id"),
            clientName = rs.getString("client_name"),
            clientCity = rs.getString("client_city"),
            teamId = rs.getInt("team_id"),
            teamName = rs.getString("team_name"),
            ownerUserId = rs.getInt("owner_user_id"),
            ownerLogin = rs.getString("owner_login"),
            ownerDisplayName = rs.getString("owner_display_name"),
            legalEntityId = rs.getInt("legal_entity_id"),
            legalEntityName = rs.getString("legal_entity_name"),
            updatedAt = rs.getLocalDateTime("updated_at"),
            rowVersion = rs.getRowVersion(),
        )
    }

    private val historyRow = RowMapper { rs, _ ->
        StageHistoryEntry(
            id = rs.getLong("id"),
            fromStage = rs.getString("from_stage"),
            toStage = rs.getString("to_stage"),
            changedAt = rs.getLocalDateTime("changed_at"),
            changedBy = rs.getIntOrNull("changed_by"),
            changedByLogin = rs.getString("changed_by_login"),
        )
    }

    private val commentRow = RowMapper { rs, _ ->
        CommentResponse(
            id = rs.getLong("id"),
            projectId = rs.getLong("project_id"),
            authorId = rs.getInt("author_id"),
            authorLogin = rs.getString("author_login"),
            authorDisplayName = rs.getString("author_display_name"),
            body = rs.getString("body"),
            createdAt = rs.getLocalDateTime("created_at"),
        )
    }

    fun search(actorId: Int, filter: ProjectFilter, afterDueDate: LocalDate?, afterId: Long?, pageSize: Int): List<ProjectResponse> =
        jdbc.sql(
            "EXEC app.project_search @actor_id = :actorId, @stage = :stage, @team_id = :teamId, " +
                "@client_id = :clientId, @owner_user_id = :ownerUserId, @overdue_only = :overdueOnly, " +
                "@due_from = :dueFrom, @due_to = :dueTo, @legal_entity_id = :legalEntityId, @after_due_date = :afterDueDate, @after_id = :afterId, " +
                "@page_size = :pageSize",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("stage", filter.stage, Types.VARCHAR)
            .param("teamId", filter.teamId, Types.INTEGER)
            .param("clientId", filter.clientId, Types.BIGINT)
            .param("ownerUserId", filter.ownerUserId, Types.INTEGER)
            .param("overdueOnly", filter.overdueOnly, Types.BIT)
            .param("dueFrom", filter.dueFrom, Types.DATE)
            .param("dueTo", filter.dueTo, Types.DATE)
            .param("legalEntityId", filter.legalEntityId, Types.INTEGER)
            .param("afterDueDate", afterDueDate, Types.DATE)
            .param("afterId", afterId, Types.BIGINT)
            .param("pageSize", pageSize, Types.INTEGER)
            .query(projectRow)
            .list()

    fun count(actorId: Int, filter: ProjectFilter): Long =
        jdbc.sql(
            "EXEC app.project_count @actor_id = :actorId, @stage = :stage, @team_id = :teamId, " +
                "@client_id = :clientId, @owner_user_id = :ownerUserId, @overdue_only = :overdueOnly, " +
                "@due_from = :dueFrom, @due_to = :dueTo, @legal_entity_id = :legalEntityId",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("stage", filter.stage, Types.VARCHAR)
            .param("teamId", filter.teamId, Types.INTEGER)
            .param("clientId", filter.clientId, Types.BIGINT)
            .param("ownerUserId", filter.ownerUserId, Types.INTEGER)
            .param("overdueOnly", filter.overdueOnly, Types.BIT)
            .param("dueFrom", filter.dueFrom, Types.DATE)
            .param("dueTo", filter.dueTo, Types.DATE)
            .param("legalEntityId", filter.legalEntityId, Types.INTEGER)
            .query { rs, _ -> rs.getLong("total") }
            .single()

    fun get(actorId: Int, id: Long): ProjectResponse =
        jdbc.sql("EXEC app.project_get @actor_id = :actorId, @id = :id")
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .query(projectRow)
            .single()

    fun create(actorId: Int, body: CreateProjectRequest): ProjectResponse =
        jdbc.sql(
            "EXEC app.project_create @actor_id = :actorId, @client_id = :clientId, @team_id = :teamId, " +
                "@owner_user_id = :ownerUserId, @name = :name, @start_date = :startDate, @due_date = :dueDate, " +
                "@budget = :budget, @legal_entity_id = :legalEntityId",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("clientId", body.clientId, Types.BIGINT)
            .param("teamId", body.teamId, Types.INTEGER)
            .param("ownerUserId", body.ownerUserId, Types.INTEGER)
            .param("name", body.name, Types.NVARCHAR)
            .param("startDate", body.startDate, Types.DATE)
            .param("dueDate", body.dueDate, Types.DATE)
            .param("budget", body.budget, Types.DECIMAL)
            .param("legalEntityId", body.legalEntityId, Types.INTEGER)
            .query(projectRow)
            .single()

    fun update(actorId: Int, id: Long, body: UpdateProjectRequest): ProjectResponse =
        jdbc.sql(
            "EXEC app.project_update @actor_id = :actorId, @id = :id, @team_id = :teamId, " +
                "@owner_user_id = :ownerUserId, @name = :name, @start_date = :startDate, @due_date = :dueDate, " +
                "@budget = :budget, @legal_entity_id = :legalEntityId, @row_version = :rowVersion",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .param("teamId", body.teamId, Types.INTEGER)
            .param("ownerUserId", body.ownerUserId, Types.INTEGER)
            .param("name", body.name, Types.NVARCHAR)
            .param("startDate", body.startDate, Types.DATE)
            .param("dueDate", body.dueDate, Types.DATE)
            .param("budget", body.budget, Types.DECIMAL)
            .param("legalEntityId", body.legalEntityId, Types.INTEGER)
            .param("rowVersion", RowVersion.parse(body.rowVersion!!), Types.BINARY)
            .query(projectRow)
            .single()

    fun changeStage(actorId: Int, id: Long, body: ChangeStageRequest): ProjectResponse =
        jdbc.sql(
            "EXEC app.project_change_stage @actor_id = :actorId, @id = :id, @to_stage = :stage, " +
                "@comment = :comment, @row_version = :rowVersion",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .param("stage", body.stage, Types.VARCHAR)
            .param("comment", body.comment, Types.NVARCHAR)
            .param("rowVersion", RowVersion.parse(body.rowVersion!!), Types.BINARY)
            .query(projectRow)
            .single()

    fun stageHistory(actorId: Int, projectId: Long): List<StageHistoryEntry> =
        jdbc.sql("EXEC app.project_stage_history_list @actor_id = :actorId, @project_id = :projectId")
            .param("actorId", actorId, Types.INTEGER)
            .param("projectId", projectId, Types.BIGINT)
            .query(historyRow)
            .list()

    fun comments(actorId: Int, projectId: Long, beforeId: Long?, pageSize: Int): List<CommentResponse> =
        jdbc.sql(
            "EXEC app.project_comment_list @actor_id = :actorId, @project_id = :projectId, " +
                "@before_id = :beforeId, @page_size = :pageSize",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("projectId", projectId, Types.BIGINT)
            .param("beforeId", beforeId, Types.BIGINT)
            .param("pageSize", pageSize, Types.INTEGER)
            .query(commentRow)
            .list()

    fun addComment(actorId: Int, projectId: Long, body: String): CommentResponse =
        jdbc.sql("EXEC app.project_comment_add @actor_id = :actorId, @project_id = :projectId, @body = :body")
            .param("actorId", actorId, Types.INTEGER)
            .param("projectId", projectId, Types.BIGINT)
            .param("body", body, Types.NVARCHAR)
            .query(commentRow)
            .single()
}
