package crm.deals

import crm.auth.CrmUserDetails
import crm.shared.RowVersion
import crm.shared.getInstant
import crm.shared.getInstantOrNull
import crm.shared.getLocalDate
import crm.shared.getLongOrNull
import crm.shared.getRowVersion
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.validation.Valid
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import org.springframework.http.HttpStatus
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.stereotype.Repository
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.math.BigDecimal
import java.sql.Types
import java.time.Instant
import java.time.LocalDate

/** A stage of the pipeline; the probability weights the forecast (ADR-0015). */
data class DealStageResponse(
    val stage: String,
    val sortOrder: Int,
    val probability: Int,
    val closed: Boolean,
    val namePl: String,
    val nameEn: String,
)

/** A deal: a chance to sell to a client, a card on the board (ADR-0015). */
data class DealResponse(
    val id: Long,
    val title: String,
    val clientId: Long,
    val clientName: String,
    val ownerUserId: Int,
    val ownerName: String,
    val stage: String,
    val probability: Int,
    val closed: Boolean,
    val value: BigDecimal,
    val currency: String,
    val expectedClose: LocalDate,
    val offerId: Long?,
    val offerNumber: String?,
    val lostReason: String?,
    val stageChangedAt: Instant,
    val closedAt: Instant?,
    val createdAt: Instant,
    val updatedAt: Instant,
    val rowVersion: String,
)

data class CreateDealRequest(
    @field:NotNull val clientId: Long?,
    @field:NotBlank @field:Size(max = 200) val title: String?,
    @field:NotNull val value: BigDecimal?,
    @field:Pattern(regexp = "PLN|EUR|USD") val currency: String?,
    @field:NotNull val expectedClose: LocalDate?,
    val offerId: Long?,
    /** An open stage to start in; LEAD when empty. */
    val stage: String?,
)

data class UpdateDealRequest(
    @field:NotBlank @field:Size(max = 200) val title: String?,
    @field:NotNull val value: BigDecimal?,
    @field:NotNull @field:Pattern(regexp = "PLN|EUR|USD") val currency: String?,
    @field:NotNull val expectedClose: LocalDate?,
    val offerId: Long?,
    @field:NotBlank @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

data class MoveDealRequest(
    @field:NotBlank val stage: String?,
    /** Required for LOST. */
    @field:Size(max = 400) val lostReason: String?,
    @field:NotBlank @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

/** The pipeline (ADR-0015): one `EXEC app.deal_*` per method. */
@Repository
class DealRepository(private val jdbc: JdbcClient) {
    private val row = RowMapper { rs, _ ->
        DealResponse(
            id = rs.getLong("id"),
            title = rs.getString("title"),
            clientId = rs.getLong("client_id"),
            clientName = rs.getString("client_name"),
            ownerUserId = rs.getInt("owner_user_id"),
            ownerName = rs.getString("owner_name"),
            stage = rs.getString("stage"),
            probability = rs.getInt("probability"),
            closed = rs.getBoolean("is_closed"),
            value = rs.getBigDecimal("value"),
            currency = rs.getString("currency"),
            expectedClose = rs.getLocalDate("expected_close"),
            offerId = rs.getLongOrNull("offer_id"),
            offerNumber = rs.getString("offer_number"),
            lostReason = rs.getString("lost_reason"),
            stageChangedAt = rs.getInstant("stage_changed_at"),
            closedAt = rs.getInstantOrNull("closed_at"),
            createdAt = rs.getInstant("created_at"),
            updatedAt = rs.getInstant("updated_at"),
            rowVersion = rs.getRowVersion(),
        )
    }

    fun stages(actorId: Int): List<DealStageResponse> =
        jdbc.sql("EXEC app.deal_stage_list @actor_id = :actorId")
            .param("actorId", actorId, Types.INTEGER)
            .query { rs, _ ->
                DealStageResponse(
                    rs.getString("stage"), rs.getInt("sort_order"), rs.getInt("probability"), rs.getBoolean("is_closed"),
                    rs.getString("name_pl"), rs.getString("name_en"),
                )
            }
            .list()

    fun board(actorId: Int, scope: String, ownerUserId: Int?, search: String?, closedDays: Int): List<DealResponse> =
        jdbc.sql(
            "EXEC app.deal_board @actor_id = :actorId, @scope = :scope, @owner_user_id = :owner, @search = :search, " +
                "@closed_days = :closedDays",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("scope", scope, Types.VARCHAR)
            .param("owner", ownerUserId, Types.INTEGER)
            .param("search", search, Types.NVARCHAR)
            .param("closedDays", closedDays, Types.INTEGER)
            .query(row)
            .list()

    fun get(actorId: Int, id: Long): DealResponse =
        jdbc.sql("EXEC app.deal_get @actor_id = :actorId, @deal_id = :id")
            .param("actorId", actorId, Types.INTEGER).param("id", id, Types.BIGINT).query(row).single()

    fun create(actorId: Int, body: CreateDealRequest): DealResponse =
        jdbc.sql(
            "EXEC app.deal_create @actor_id = :actorId, @client_id = :clientId, @title = :title, @value = :value, " +
                "@currency = :currency, @expected_close = :expectedClose, @offer_id = :offerId, @stage = :stage",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("clientId", body.clientId, Types.BIGINT)
            .param("title", body.title, Types.NVARCHAR)
            .param("value", body.value, Types.DECIMAL)
            .param("currency", body.currency ?: "PLN", Types.CHAR)
            .param("expectedClose", body.expectedClose, Types.DATE)
            .param("offerId", body.offerId, Types.BIGINT)
            .param("stage", body.stage, Types.VARCHAR)
            .query(row)
            .single()

    fun update(actorId: Int, id: Long, body: UpdateDealRequest): DealResponse =
        jdbc.sql(
            "EXEC app.deal_update @actor_id = :actorId, @deal_id = :id, @title = :title, @value = :value, " +
                "@currency = :currency, @expected_close = :expectedClose, @offer_id = :offerId, @row_version = :rowVersion",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .param("title", body.title, Types.NVARCHAR)
            .param("value", body.value, Types.DECIMAL)
            .param("currency", body.currency, Types.CHAR)
            .param("expectedClose", body.expectedClose, Types.DATE)
            .param("offerId", body.offerId, Types.BIGINT)
            .param("rowVersion", RowVersion.parse(body.rowVersion!!), Types.BINARY)
            .query(row)
            .single()

    fun move(actorId: Int, id: Long, body: MoveDealRequest): DealResponse =
        jdbc.sql(
            "EXEC app.deal_move @actor_id = :actorId, @deal_id = :id, @stage = :stage, @lost_reason = :lostReason, " +
                "@row_version = :rowVersion",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .param("stage", body.stage, Types.VARCHAR)
            .param("lostReason", body.lostReason, Types.NVARCHAR)
            .param("rowVersion", RowVersion.parse(body.rowVersion!!), Types.BINARY)
            .query(row)
            .single()

    fun delete(actorId: Int, id: Long, rowVersion: String) {
        jdbc.sql("EXEC app.deal_delete @actor_id = :actorId, @deal_id = :id, @row_version = :rowVersion")
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .param("rowVersion", RowVersion.parse(rowVersion), Types.BINARY)
            .update()
    }
}

/** The sales pipeline as a kanban board (ADR-0015). SALES see the deals of their own clients. */
@Tag(name = "Deals")
@RestController
@RequestMapping("/api/deals")
class DealController(private val deals: DealRepository) {

    @Operation(summary = "The stages of the pipeline, in order, with their probability.")
    @GetMapping("/stages")
    fun listDealStages(@AuthenticationPrincipal actor: CrmUserDetails): List<DealStageResponse> = deals.stages(actor.id)

    @Operation(
        summary = "The board: open deals and the ones closed in the last closedDays days. scope MINE or ALL, " +
            "ownerUserId (one salesperson), search (title or client prefix).",
    )
    @GetMapping
    fun dealBoard(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(defaultValue = "ALL") scope: String,
        @RequestParam(required = false) ownerUserId: Int?,
        @RequestParam(required = false) search: String?,
        @RequestParam(defaultValue = "30") @Min(0) @Max(365) closedDays: Int,
    ): List<DealResponse> = deals.board(actor.id, scope, ownerUserId, search, closedDays)

    @Operation(summary = "Deal details.")
    @GetMapping("/{id}")
    fun getDeal(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Long): DealResponse = deals.get(actor.id, id)

    @Operation(summary = "Open a deal for a client (SALES: own clients); the owner is the client's salesperson.")
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    fun createDeal(@AuthenticationPrincipal actor: CrmUserDetails, @Valid @RequestBody body: CreateDealRequest): DealResponse =
        deals.create(actor.id, body)

    @Operation(summary = "Change a deal's title, value, currency, expected close and offer. rowVersion required.")
    @PutMapping("/{id}")
    fun updateDeal(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: UpdateDealRequest,
    ): DealResponse = deals.update(actor.id, id, body)

    @Operation(summary = "Move a deal to a stage (a column of the board); LOST needs lostReason.")
    @PostMapping("/{id}/move")
    fun moveDeal(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: MoveDealRequest,
    ): DealResponse = deals.move(actor.id, id, body)

    @Operation(summary = "Delete a deal opened by mistake.")
    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun deleteDeal(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @RequestParam @Pattern(regexp = RowVersion.PATTERN) rowVersion: String,
    ) = deals.delete(actor.id, id, rowVersion)
}
