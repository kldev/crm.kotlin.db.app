package crm.offers

import crm.shared.RowVersion
import crm.shared.getInstant
import crm.shared.getInstantOrNull
import crm.shared.getLocalDate
import crm.shared.getRowVersion
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository
import tools.jackson.databind.json.JsonMapper
import java.sql.Types

data class OfferFilter(val status: String?, val templateKey: String?, val clientId: Long?, val search: String?)

/** Offers (ADR-0013): one `EXEC app.offer_*` (or `app.user_contact_*`) per method. */
@Repository
class OfferRepository(private val jdbc: JdbcClient, private val json: JsonMapper) {

    private val offerRow = RowMapper { rs, _ ->
        OfferResponse(
            id = rs.getLong("id"),
            number = rs.getString("number"),
            clientId = rs.getLong("client_id"),
            clientName = rs.getString("client_name"),
            clientNip = rs.getString("client_nip"),
            clientCity = rs.getString("client_city"),
            clientEmail = rs.getString("client_email"),
            templateKey = rs.getString("template_key"),
            templateNamePl = rs.getString("template_name_pl"),
            templateNameEn = rs.getString("template_name_en"),
            title = rs.getString("title"),
            intro = rs.getString("intro"),
            terms = rs.getString("terms"),
            currency = rs.getString("currency"),
            validUntil = rs.getLocalDate("valid_until"),
            status = rs.getString("status"),
            authorUserId = rs.getInt("author_user_id"),
            authorName = rs.getString("author_name"),
            authorRole = rs.getString("author_role"),
            authorJobTitle = rs.getString("author_job_title"),
            authorPhone = rs.getString("author_phone"),
            authorEmail = rs.getString("author_email"),
            sentAt = rs.getInstantOrNull("sent_at"),
            decidedAt = rs.getInstantOrNull("decided_at"),
            createdAt = rs.getInstant("created_at"),
            updatedAt = rs.getInstant("updated_at"),
            itemCount = rs.getInt("item_count"),
            totalNet = rs.getBigDecimal("total_net"),
            totalVat = rs.getBigDecimal("total_vat"),
            totalGross = rs.getBigDecimal("total_gross"),
            rowVersion = rs.getRowVersion(),
        )
    }

    private val contactRow = RowMapper { rs, _ ->
        UserContactResponse(rs.getInt("id"), rs.getString("display_name"), rs.getString("job_title"), rs.getString("phone"), rs.getString("email"))
    }

    fun templates(actorId: Int): List<OfferTemplateResponse> =
        jdbc.sql("EXEC app.offer_template_list @actor_id = :actorId")
            .param("actorId", actorId, Types.INTEGER)
            .query { rs, _ ->
                OfferTemplateResponse(
                    rs.getString("template_key"), rs.getString("name_pl"), rs.getString("name_en"), rs.getString("title_pl"),
                    rs.getString("title_en"), rs.getInt("validity_days"), rs.getInt("item_count"),
                )
            }
            .list()

    fun search(actorId: Int, filter: OfferFilter, afterId: Long?, size: Int): List<OfferResponse> =
        jdbc.sql(
            "EXEC app.offer_search @actor_id = :actorId, @status = :status, @template_key = :templateKey, " +
                "@client_id = :clientId, @search = :search, @after_id = :afterId, @page_size = :size",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("status", filter.status, Types.VARCHAR)
            .param("templateKey", filter.templateKey, Types.VARCHAR)
            .param("clientId", filter.clientId, Types.BIGINT)
            .param("search", filter.search, Types.NVARCHAR)
            .param("afterId", afterId, Types.BIGINT)
            .param("size", size, Types.INTEGER)
            .query(offerRow)
            .list()

    fun count(actorId: Int, filter: OfferFilter): Long =
        jdbc.sql(
            "EXEC app.offer_count @actor_id = :actorId, @status = :status, @template_key = :templateKey, " +
                "@client_id = :clientId, @search = :search",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("status", filter.status, Types.VARCHAR)
            .param("templateKey", filter.templateKey, Types.VARCHAR)
            .param("clientId", filter.clientId, Types.BIGINT)
            .param("search", filter.search, Types.NVARCHAR)
            .query { rs, _ -> rs.getLong("total") }
            .single()

    fun get(actorId: Int, offerId: Long): OfferResponse =
        jdbc.sql("EXEC app.offer_get @actor_id = :actorId, @offer_id = :offerId")
            .param("actorId", actorId, Types.INTEGER)
            .param("offerId", offerId, Types.BIGINT)
            .query(offerRow)
            .single()

    fun items(actorId: Int, offerId: Long): List<OfferItemResponse> =
        jdbc.sql("EXEC app.offer_item_list @actor_id = :actorId, @offer_id = :offerId")
            .param("actorId", actorId, Types.INTEGER)
            .param("offerId", offerId, Types.BIGINT)
            .query { rs, _ ->
                OfferItemResponse(
                    rs.getInt("line_no"), rs.getString("description"), rs.getString("unit"), rs.getBigDecimal("quantity"),
                    rs.getBigDecimal("unit_price"), rs.getInt("vat_rate"), rs.getBigDecimal("net"), rs.getBigDecimal("vat"),
                    rs.getBigDecimal("gross"),
                )
            }
            .list()

    fun create(actorId: Int, body: CreateOfferRequest): OfferResponse =
        jdbc.sql(
            "EXEC app.offer_create @actor_id = :actorId, @client_id = :clientId, @template_key = :templateKey, " +
                "@title = :title, @lang = :lang",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("clientId", body.clientId, Types.BIGINT)
            .param("templateKey", body.templateKey, Types.VARCHAR)
            .param("title", body.title, Types.NVARCHAR)
            .param("lang", body.lang ?: "pl", Types.CHAR)
            .query(offerRow)
            .single()

    fun update(actorId: Int, offerId: Long, body: UpdateOfferRequest): OfferResponse =
        jdbc.sql(
            "EXEC app.offer_update @actor_id = :actorId, @offer_id = :offerId, @title = :title, @intro = :intro, " +
                "@terms = :terms, @currency = :currency, @valid_until = :validUntil, @items = :items, " +
                "@row_version = :rowVersion",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("offerId", offerId, Types.BIGINT)
            .param("title", body.title, Types.NVARCHAR)
            .param("intro", body.intro, Types.NVARCHAR)
            .param("terms", body.terms, Types.NVARCHAR)
            .param("currency", body.currency, Types.CHAR)
            .param("validUntil", body.validUntil, Types.DATE)
            .param("items", json.writeValueAsString(body.items), Types.NVARCHAR)
            .param("rowVersion", RowVersion.parse(body.rowVersion!!), Types.BINARY)
            .query(offerRow)
            .single()

    fun changeStatus(actorId: Int, offerId: Long, status: String, rowVersion: String): OfferResponse =
        jdbc.sql(
            "EXEC app.offer_change_status @actor_id = :actorId, @offer_id = :offerId, @status = :status, " +
                "@row_version = :rowVersion",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("offerId", offerId, Types.BIGINT)
            .param("status", status, Types.VARCHAR)
            .param("rowVersion", RowVersion.parse(rowVersion), Types.BINARY)
            .query(offerRow)
            .single()

    fun delete(actorId: Int, offerId: Long, rowVersion: String) {
        jdbc.sql("EXEC app.offer_delete @actor_id = :actorId, @offer_id = :offerId, @row_version = :rowVersion")
            .param("actorId", actorId, Types.INTEGER)
            .param("offerId", offerId, Types.BIGINT)
            .param("rowVersion", RowVersion.parse(rowVersion), Types.BINARY)
            .update()
    }

    fun contact(actorId: Int, userId: Int): UserContactResponse =
        jdbc.sql("EXEC app.user_contact_get @actor_id = :actorId, @user_id = :userId")
            .param("actorId", actorId, Types.INTEGER)
            .param("userId", userId, Types.INTEGER)
            .query(contactRow)
            .single()

    fun updateContact(actorId: Int, userId: Int, body: UpdateContactRequest): UserContactResponse =
        jdbc.sql(
            "EXEC app.user_contact_update @actor_id = :actorId, @user_id = :userId, @job_title = :jobTitle, " +
                "@phone = :phone, @email = :email",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("userId", userId, Types.INTEGER)
            .param("jobTitle", body.jobTitle, Types.NVARCHAR)
            .param("phone", body.phone, Types.VARCHAR)
            .param("email", body.email, Types.VARCHAR)
            .query(contactRow)
            .single()
}
