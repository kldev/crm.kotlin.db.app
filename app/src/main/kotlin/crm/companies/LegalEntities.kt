package crm.companies

import crm.auth.CrmUserDetails
import crm.shared.RowVersion
import crm.shared.getInstant
import crm.shared.getLocalDate
import crm.shared.getRowVersion
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.validation.Valid
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import org.springframework.http.HttpStatus
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.stereotype.Repository
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.time.Instant
import java.time.LocalDate

/** One of the group's own companies, which deliver projects and sign offers (ADR-0016) - not a client. */
data class LegalEntityResponse(
    val id: Int,
    val name: String,
    val legalName: String,
    val taxId: String,
    val vatNumber: String?,
    val address: String,
    val phone: String?,
    val email: String?,
    val website: String?,
    val bankAccount: String?,
    val activeFrom: LocalDate,
    /** The last trading day of a closed company; null while it trades. */
    val activeTo: LocalDate?,
    /** Trades today. */
    val trading: Boolean,
    val offers: Long,
    val updatedAt: Instant,
    val rowVersion: String,
) {
    /** NIP as people write it: 525-000-00-15. */
    val taxIdFormatted: String
        get() = "${taxId.take(3)}-${taxId.substring(3, 6)}-${taxId.substring(6, 8)}-${taxId.substring(8)}"
}

data class LegalEntityRequest(
    @field:NotBlank @field:Size(max = 100) val name: String?,
    @field:NotBlank @field:Size(max = 200) val legalName: String?,
    @field:NotBlank @field:Size(max = 20) val taxId: String?,
    @field:Size(max = 20) val vatNumber: String?,
    @field:NotBlank @field:Size(max = 300) val address: String?,
    @field:Size(max = 30) val phone: String?,
    @field:Size(max = 254) val email: String?,
    @field:Size(max = 200) val website: String?,
    @field:Size(max = 40) val bankAccount: String?,
    @field:NotNull val activeFrom: LocalDate?,
    val activeTo: LocalDate?,
    /** Required to update; ignored on create. */
    @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

/** The group's companies: one `EXEC app.legal_entity_*` per method. */
@Repository
class LegalEntityRepository(private val jdbc: JdbcClient) {
    private val row = RowMapper { rs, _ ->
        LegalEntityResponse(
            id = rs.getInt("id"),
            name = rs.getString("name"),
            legalName = rs.getString("legal_name"),
            taxId = rs.getString("tax_id"),
            vatNumber = rs.getString("vat_number"),
            address = rs.getString("address"),
            phone = rs.getString("phone"),
            email = rs.getString("email"),
            website = rs.getString("website"),
            bankAccount = rs.getString("bank_account"),
            activeFrom = rs.getLocalDate("active_from"),
            activeTo = rs.getObject("active_to", LocalDate::class.java),
            trading = rs.getBoolean("is_trading"),
            offers = rs.getLong("offers"),
            updatedAt = rs.getInstant("updated_at"),
            rowVersion = rs.getRowVersion(),
        )
    }

    fun list(actorId: Int): List<LegalEntityResponse> =
        jdbc.sql("EXEC app.legal_entity_list @actor_id = :actorId").param("actorId", actorId).query(row).list()

    fun get(actorId: Int, id: Int): LegalEntityResponse =
        jdbc.sql("EXEC app.legal_entity_get @actor_id = :actorId, @legal_entity_id = :id")
            .param("actorId", actorId).param("id", id).query(row).single()

    fun save(actorId: Int, id: Int?, body: LegalEntityRequest): LegalEntityResponse =
        jdbc.sql(
            "EXEC app.legal_entity_save @actor_id = :actorId, @legal_entity_id = :id, @name = :name, " +
                "@legal_name = :legalName, @tax_id = :taxId, @vat_number = :vatNumber, @address = :address, " +
                "@phone = :phone, @email = :email, @website = :website, @bank_account = :bankAccount, " +
                "@active_from = :activeFrom, @active_to = :activeTo, @row_version = :rowVersion",
        )
            .param("actorId", actorId, java.sql.Types.INTEGER)
            .param("id", id, java.sql.Types.INTEGER)
            .param("name", body.name, java.sql.Types.NVARCHAR)
            .param("legalName", body.legalName, java.sql.Types.NVARCHAR)
            .param("taxId", body.taxId, java.sql.Types.VARCHAR)
            .param("vatNumber", body.vatNumber, java.sql.Types.VARCHAR)
            .param("address", body.address, java.sql.Types.NVARCHAR)
            .param("phone", body.phone, java.sql.Types.VARCHAR)
            .param("email", body.email, java.sql.Types.NVARCHAR)
            .param("website", body.website, java.sql.Types.NVARCHAR)
            .param("bankAccount", body.bankAccount, java.sql.Types.VARCHAR)
            .param("activeFrom", body.activeFrom, java.sql.Types.DATE)
            .param("activeTo", body.activeTo, java.sql.Types.DATE)
            .param("rowVersion", body.rowVersion?.let(RowVersion::parse), java.sql.Types.BINARY)
            .query(row)
            .single()
}

/** The group's companies (ADR-0016): everybody reads them (pickers), administrators manage them. */
@Tag(name = "Legal entities")
@RestController
@RequestMapping("/api/legal-entities")
class LegalEntityController(private val entities: LegalEntityRepository) {

    @Operation(summary = "The group's companies, with whether each trades today.")
    @GetMapping
    fun listLegalEntities(@AuthenticationPrincipal actor: CrmUserDetails): List<LegalEntityResponse> = entities.list(actor.id)

    @Operation(summary = "One company.")
    @GetMapping("/{id}")
    fun getLegalEntity(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Int): LegalEntityResponse =
        entities.get(actor.id, id)

    @Operation(summary = "Add a company (ADMIN).")
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    fun createLegalEntity(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @Valid @RequestBody body: LegalEntityRequest,
    ): LegalEntityResponse = entities.save(actor.id, null, body)

    @Operation(summary = "Change a company, or close it with activeTo (ADMIN). rowVersion required.")
    @PutMapping("/{id}")
    fun updateLegalEntity(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Int,
        @Valid @RequestBody body: LegalEntityRequest,
    ): LegalEntityResponse = entities.save(actor.id, id, body)
}
