package crm.desk

import crm.shared.getInstant
import crm.shared.getInstantOrNull
import crm.shared.getIntOrNull
import crm.shared.toUtcLocalDateTime
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository
import java.sql.Types
import java.time.Instant

data class TicketFilter(
    /** POOL, MINE or ALL. */
    val scope: String,
    val categoryKey: String?,
    val subcategoryKey: String?,
    val priority: String?,
    /** OVERDUE or DUE_SOON. */
    val deadline: String?,
    /** OPEN or DONE. */
    val completion: String?,
    val search: String?,
)

/** Keyset position in the tickets list: phase 0 = open (by deadline), 1 = resolved (newest first). */
data class TicketKey(val phase: Int, val time: Instant, val id: Long)

/** The service desk (ADR-0007). Every method is one `EXEC app.desk_<procedure>`; the rules live in the procedures. */
@Repository
class DeskRepository(private val jdbc: JdbcClient) {

    private val ticketRow = RowMapper { rs, _ ->
        TicketResponse(
            id = rs.getLong("id"),
            number = rs.getString("number"),
            title = rs.getString("title"),
            description = rs.getString("description"),
            categoryKey = rs.getString("category_key"),
            subcategoryKey = rs.getString("subcategory_key"),
            priority = rs.getString("priority"),
            originalPriority = rs.getString("original_priority"),
            reportedAt = rs.getInstant("reported_at"),
            deadline = rs.getInstant("deadline"),
            status = rs.getString("status"),
            assigneeUserId = rs.getIntOrNull("assignee_user_id"),
            assigneeName = rs.getString("assignee_name"),
            handlerPersonId = rs.getIntOrNull("handler_person_id"),
            handlerName = rs.getString("handler_name"),
            requesterIncognito = rs.getBoolean("requester_incognito"),
            requesterPersonId = rs.getIntOrNull("requester_person_id"),
            requesterName = rs.getString("requester_name"),
            channel = rs.getString("channel"),
            registeredByName = rs.getString("registered_by_name"),
            recordedAt = rs.getInstant("recorded_at"),
            resolvedAt = rs.getInstantOrNull("resolved_at"),
            resolvedLate = rs.getBoolean("resolved_late"),
            commentCount = rs.getInt("comment_count"),
            attachmentCount = rs.getInt("attachment_count"),
            version = rs.getInt("version"),
            lastChangeAt = rs.getInstant("last_change_at"),
        )
    }

    fun report(actorId: Int, body: ReportTicketRequest): TicketResponse =
        jdbc.sql(
            "EXEC app.desk_ticket_report @actor_id = :actorId, @title = :title, @description = :description, " +
                "@category_key = :categoryKey, @subcategory_key = :subcategoryKey, @priority = :priority, " +
                "@reported_at = :reportedAt, @requester_person_id = :personId, @requester_incognito = :incognito",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("title", body.title, Types.NVARCHAR)
            .param("description", body.description, Types.NVARCHAR)
            .param("categoryKey", body.categoryKey, Types.VARCHAR)
            .param("subcategoryKey", body.subcategoryKey, Types.VARCHAR)
            .param("priority", body.priority, Types.VARCHAR)
            .param("reportedAt", body.reportedAt?.toUtcLocalDateTime(), Types.TIMESTAMP)
            .param("personId", body.requesterPersonId, Types.INTEGER)
            .param("incognito", body.requesterIncognito ?: false, Types.BIT)
            .query(ticketRow)
            .single()

    fun reportPublic(body: PublicReportRequest): PublicReportResponse =
        jdbc.sql(
            "EXEC app.desk_ticket_report_public @title = :title, @description = :description, " +
                "@category_key = :categoryKey, @subcategory_key = :subcategoryKey, @priority = :priority, " +
                "@requester_person_id = :personId, @requester_incognito = :incognito",
        )
            .param("title", body.title, Types.NVARCHAR)
            .param("description", body.description, Types.NVARCHAR)
            .param("categoryKey", body.categoryKey, Types.VARCHAR)
            .param("subcategoryKey", body.subcategoryKey, Types.VARCHAR)
            .param("priority", body.priority, Types.VARCHAR)
            .param("personId", body.requesterPersonId, Types.INTEGER)
            .param("incognito", body.requesterIncognito ?: false, Types.BIT)
            .query { rs, _ -> PublicReportResponse(rs.getString("number"), rs.getInstant("deadline")) }
            .single()

    fun search(actorId: Int, filter: TicketFilter, after: TicketKey?, pageSize: Int): List<TicketResponse> =
        jdbc.sql(
            "EXEC app.desk_ticket_search @actor_id = :actorId, @scope = :scope, @category_key = :categoryKey, " +
                "@subcategory_key = :subcategoryKey, @priority = :priority, @deadline = :deadline, " +
                "@completion = :completion, @search = :search, @after_phase = :afterPhase, " +
                "@after_time = :afterTime, @after_id = :afterId, @page_size = :pageSize",
        )
            .param("actorId", actorId, Types.INTEGER)
            .filterParams(filter)
            .param("afterPhase", after?.phase, Types.TINYINT)
            .param("afterTime", after?.time?.toUtcLocalDateTime(), Types.TIMESTAMP)
            .param("afterId", after?.id, Types.BIGINT)
            .param("pageSize", pageSize, Types.INTEGER)
            .query(ticketRow)
            .list()

    fun count(actorId: Int, filter: TicketFilter): Long =
        jdbc.sql(
            "EXEC app.desk_ticket_count @actor_id = :actorId, @scope = :scope, @category_key = :categoryKey, " +
                "@subcategory_key = :subcategoryKey, @priority = :priority, @deadline = :deadline, " +
                "@completion = :completion, @search = :search",
        )
            .param("actorId", actorId, Types.INTEGER)
            .filterParams(filter)
            .query { rs, _ -> rs.getLong("total") }
            .single()

    private fun JdbcClient.StatementSpec.filterParams(filter: TicketFilter) = this
        .param("scope", filter.scope, Types.VARCHAR)
        .param("categoryKey", filter.categoryKey, Types.VARCHAR)
        .param("subcategoryKey", filter.subcategoryKey, Types.VARCHAR)
        .param("priority", filter.priority, Types.VARCHAR)
        .param("deadline", filter.deadline, Types.VARCHAR)
        .param("completion", filter.completion, Types.VARCHAR)
        .param("search", filter.search, Types.NVARCHAR)

    fun counters(actorId: Int): TicketCounters =
        jdbc.sql("EXEC app.desk_ticket_counters @actor_id = :actorId")
            .param("actorId", actorId, Types.INTEGER)
            .query { rs, _ -> TicketCounters(rs.getInt("overdue"), rs.getInt("due_soon"), rs.getInt("pool"), rs.getInt("mine")) }
            .single()

    fun get(actorId: Int, ticketId: Long): TicketResponse =
        jdbc.sql("EXEC app.desk_ticket_get @actor_id = :actorId, @ticket_id = :ticketId")
            .param("actorId", actorId, Types.INTEGER)
            .param("ticketId", ticketId, Types.BIGINT)
            .query(ticketRow)
            .single()

    fun find(actorId: Int, number: String): TicketResponse =
        jdbc.sql("EXEC app.desk_ticket_find @actor_id = :actorId, @number = :number")
            .param("actorId", actorId, Types.INTEGER)
            .param("number", number, Types.VARCHAR)
            .query(ticketRow)
            .single()

    fun events(actorId: Int, ticketId: Long): List<TicketEventResponse> =
        jdbc.sql("EXEC app.desk_ticket_event_list @actor_id = :actorId, @ticket_id = :ticketId")
            .param("actorId", actorId, Types.INTEGER)
            .param("ticketId", ticketId, Types.BIGINT)
            .query { rs, _ ->
                TicketEventResponse(
                    version = rs.getInt("version"),
                    type = rs.getString("event_type"),
                    at = rs.getInstant("at"),
                    actorUserId = rs.getIntOrNull("actor_user_id"),
                    actorName = rs.getString("actor_name"),
                    data = rs.getString("data"),
                )
            }
            .list()

    fun take(actorId: Int, ticketId: Long): TicketResponse = action("EXEC app.desk_ticket_take @actor_id = :actorId, @ticket_id = :ticketId", actorId, ticketId) { this }

    fun handOver(actorId: Int, ticketId: Long, body: HandOverRequest): TicketResponse =
        action(
            "EXEC app.desk_ticket_hand_over @actor_id = :actorId, @ticket_id = :ticketId, @to_user_id = :toUserId, @reason = :reason",
            actorId,
            ticketId,
        ) {
            param("toUserId", body.toUserId, Types.INTEGER).param("reason", body.reason, Types.NVARCHAR)
        }

    fun returnToPool(actorId: Int, ticketId: Long, body: ReasonRequest): TicketResponse =
        action("EXEC app.desk_ticket_return @actor_id = :actorId, @ticket_id = :ticketId, @reason = :reason", actorId, ticketId) {
            param("reason", body.reason, Types.NVARCHAR)
        }

    fun changePriority(actorId: Int, ticketId: Long, body: ChangePriorityRequest): TicketResponse =
        action(
            "EXEC app.desk_ticket_change_priority @actor_id = :actorId, @ticket_id = :ticketId, @priority = :priority, @reason = :reason",
            actorId,
            ticketId,
        ) {
            param("priority", body.priority, Types.VARCHAR).param("reason", body.reason, Types.NVARCHAR)
        }

    fun resolve(actorId: Int, ticketId: Long): TicketResponse =
        action("EXEC app.desk_ticket_resolve @actor_id = :actorId, @ticket_id = :ticketId", actorId, ticketId) { this }

    fun comment(actorId: Int, ticketId: Long, body: CommentRequest): TicketResponse =
        action("EXEC app.desk_ticket_comment @actor_id = :actorId, @ticket_id = :ticketId, @text = :text", actorId, ticketId) {
            param("text", body.text, Types.NVARCHAR)
        }

    fun assignHandler(actorId: Int, ticketId: Long, body: AssignHandlerRequest): TicketResponse =
        action(
            "EXEC app.desk_ticket_assign_handler @actor_id = :actorId, @ticket_id = :ticketId, @person_id = :personId, @reason = :reason",
            actorId,
            ticketId,
        ) {
            param("personId", body.personId, Types.INTEGER).param("reason", body.reason, Types.NVARCHAR)
        }

    /** One ticket action: [sql] takes :actorId and :ticketId plus its own parameters; returns the changed ticket. */
    private fun action(
        sql: String,
        actorId: Int,
        ticketId: Long,
        bind: JdbcClient.StatementSpec.() -> JdbcClient.StatementSpec,
    ): TicketResponse =
        jdbc.sql(sql)
            .param("actorId", actorId, Types.INTEGER)
            .param("ticketId", ticketId, Types.BIGINT)
            // Not named `params`: StatementSpec has a params(vararg) method that would be called instead.
            .bind()
            .query(ticketRow)
            .single()

    fun agents(actorId: Int, search: String?, afterName: String?, afterId: Int?, pageSize: Int): List<AgentSummary> =
        jdbc.sql(
            "EXEC app.desk_agent_list @actor_id = :actorId, @search = :search, @after_name = :afterName, " +
                "@after_id = :afterId, @page_size = :pageSize",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("search", search, Types.NVARCHAR)
            .param("afterName", afterName, Types.NVARCHAR)
            .param("afterId", afterId, Types.INTEGER)
            .param("pageSize", pageSize, Types.INTEGER)
            .query { rs, _ ->
                AgentSummary(
                    rs.getInt("id"), rs.getString("login"), rs.getString("display_name"), rs.getString("role"),
                    rs.getInt("in_progress"),
                )
            }
            .list()

    fun people(actorId: Int): List<PersonResponse> =
        jdbc.sql("EXEC app.desk_person_list @actor_id = :actorId")
            .param("actorId", actorId, Types.INTEGER)
            .query { rs, _ ->
                PersonResponse(
                    rs.getInt("id"), rs.getString("first_name"), rs.getString("last_name"),
                    rs.getString("department"), rs.getString("email"), rs.getString("phone"),
                )
            }
            .list()

    fun publicPeople(): List<PublicPerson> =
        jdbc.sql("EXEC app.desk_public_person_list")
            .query { rs, _ ->
                PublicPerson(rs.getInt("id"), rs.getString("first_name"), rs.getString("last_name"), rs.getString("department"))
            }
            .list()

    fun catalog(): DeskCatalog {
        data class Row(val category: CategoryResponse, val sub: SubcategoryResponse)

        val rows = jdbc.sql("EXEC app.desk_catalog_list")
            .query { rs, _ ->
                Row(
                    CategoryResponse(rs.getString("category_key"), rs.getString("category_name"), rs.getString("department"), emptyList()),
                    SubcategoryResponse(
                        rs.getString("subcategory_key"), rs.getString("subcategory_name"), rs.getString("market"),
                        rs.getBoolean("is_active"),
                    ),
                )
            }
            .list()
        // Rows come in catalog order; group them keeping it.
        val categories = rows.groupBy { it.category.key }.values.map { group ->
            group.first().category.copy(subcategories = group.map { it.sub })
        }
        val priorities = jdbc.sql("EXEC app.desk_priority_list")
            .query { rs, _ -> PriorityResponse(rs.getString("priority"), rs.getInt("sla_minutes")) }
            .list()
        return DeskCatalog(categories, priorities)
    }
}
