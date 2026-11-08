package crm.clients

import crm.shared.RowVersion
import crm.shared.getIntOrNull
import crm.shared.getLocalDateTime
import crm.shared.getRowVersion
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository
import java.sql.Types

data class ClientFilter(
    val namePrefix: String?,
    val nip: String?,
    val email: String?,
    val city: String?,
    val status: String?,
)

/** Clients. Every method is one `EXEC app.<procedure>`; rules and visibility live in the procedures. */
@Repository
class ClientRepository(private val jdbc: JdbcClient) {

    private val summaryRow = RowMapper { rs, _ ->
        ClientSummary(
            id = rs.getLong("id"),
            name = rs.getString("name"),
            nip = rs.getString("nip"),
            email = rs.getString("email"),
            phone = rs.getString("phone"),
            city = rs.getString("city"),
            status = rs.getString("status"),
            assignedUserId = rs.getIntOrNull("assigned_user_id"),
            assignedUserLogin = rs.getString("assigned_user_login"),
            createdAt = rs.getLocalDateTime("created_at"),
            updatedAt = rs.getLocalDateTime("updated_at"),
            rowVersion = rs.getRowVersion(),
        )
    }

    private val clientRow = RowMapper { rs, _ ->
        ClientResponse(
            id = rs.getLong("id"),
            name = rs.getString("name"),
            nip = rs.getString("nip"),
            email = rs.getString("email"),
            phone = rs.getString("phone"),
            city = rs.getString("city"),
            status = rs.getString("status"),
            assignedUserId = rs.getIntOrNull("assigned_user_id"),
            assignedUserLogin = rs.getString("assigned_user_login"),
            note = rs.getString("note"),
            createdAt = rs.getLocalDateTime("created_at"),
            createdBy = rs.getIntOrNull("created_by"),
            updatedAt = rs.getLocalDateTime("updated_at"),
            updatedBy = rs.getIntOrNull("updated_by"),
            rowVersion = rs.getRowVersion(),
        )
    }

    fun search(actorId: Int, filter: ClientFilter, afterId: Long?, afterName: String?, pageSize: Int): List<ClientSummary> =
        jdbc.sql(
            "EXEC app.client_search @actor_id = :actorId, @name_prefix = :namePrefix, @nip = :nip, " +
                "@email = :email, @city = :city, @status = :status, @after_id = :afterId, " +
                "@after_name = :afterName, @page_size = :pageSize",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("namePrefix", filter.namePrefix, Types.NVARCHAR)
            .param("nip", filter.nip, Types.VARCHAR)
            .param("email", filter.email, Types.VARCHAR)
            .param("city", filter.city, Types.NVARCHAR)
            .param("status", filter.status, Types.VARCHAR)
            .param("afterId", afterId, Types.BIGINT)
            .param("afterName", afterName, Types.NVARCHAR)
            .param("pageSize", pageSize, Types.INTEGER)
            .query(summaryRow)
            .list()

    fun count(actorId: Int, filter: ClientFilter): Long =
        jdbc.sql(
            "EXEC app.client_count @actor_id = :actorId, @name_prefix = :namePrefix, @nip = :nip, " +
                "@email = :email, @city = :city, @status = :status",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("namePrefix", filter.namePrefix, Types.NVARCHAR)
            .param("nip", filter.nip, Types.VARCHAR)
            .param("email", filter.email, Types.VARCHAR)
            .param("city", filter.city, Types.NVARCHAR)
            .param("status", filter.status, Types.VARCHAR)
            .query { rs, _ -> rs.getLong("total") }
            .single()

    fun get(actorId: Int, id: Long): ClientResponse =
        jdbc.sql("EXEC app.client_get @actor_id = :actorId, @id = :id")
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .query(clientRow)
            .single()

    fun create(actorId: Int, body: ClientRequest): ClientResponse =
        jdbc.sql(
            "EXEC app.client_create @actor_id = :actorId, @name = :name, @nip = :nip, @email = :email, " +
                "@phone = :phone, @city = :city, @status = :status, @assigned_user_id = :assignedUserId, @note = :note",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("name", body.name, Types.NVARCHAR)
            .param("nip", body.nip, Types.VARCHAR)
            .param("email", body.email, Types.VARCHAR)
            .param("phone", body.phone, Types.VARCHAR)
            .param("city", body.city, Types.NVARCHAR)
            .param("status", body.status, Types.VARCHAR)
            .param("assignedUserId", body.assignedUserId, Types.INTEGER)
            .param("note", body.note, Types.NVARCHAR)
            .query(clientRow)
            .single()

    fun update(actorId: Int, id: Long, body: ClientRequest, rowVersion: String): ClientResponse =
        jdbc.sql(
            "EXEC app.client_update @actor_id = :actorId, @id = :id, @name = :name, @nip = :nip, @email = :email, " +
                "@phone = :phone, @city = :city, @status = :status, @assigned_user_id = :assignedUserId, " +
                "@note = :note, @row_version = :rowVersion",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .param("name", body.name, Types.NVARCHAR)
            .param("nip", body.nip, Types.VARCHAR)
            .param("email", body.email, Types.VARCHAR)
            .param("phone", body.phone, Types.VARCHAR)
            .param("city", body.city, Types.NVARCHAR)
            .param("status", body.status, Types.VARCHAR)
            .param("assignedUserId", body.assignedUserId, Types.INTEGER)
            .param("note", body.note, Types.NVARCHAR)
            .param("rowVersion", RowVersion.parse(rowVersion), Types.BINARY)
            .query(clientRow)
            .single()

    fun delete(actorId: Int, id: Long, rowVersion: String) {
        jdbc.sql("EXEC app.client_delete @actor_id = :actorId, @id = :id, @row_version = :rowVersion")
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .param("rowVersion", RowVersion.parse(rowVersion), Types.BINARY)
            .update()
    }
}
