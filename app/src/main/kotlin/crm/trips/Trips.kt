package crm.trips

import crm.auth.CrmUserDetails
import crm.shared.Cursor
import crm.shared.InvalidCursorException
import crm.shared.PageResponse
import crm.shared.RowVersion
import crm.shared.TotalResponse
import crm.shared.getInstant
import crm.shared.getInstantOrNull
import crm.shared.getIntOrNull
import crm.shared.getLocalDate
import crm.shared.getLongOrNull
import crm.shared.getRowVersion
import crm.shared.toUtcLocalDateTime
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.validation.Valid
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import org.springframework.format.annotation.DateTimeFormat
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
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import tools.jackson.databind.json.JsonMapper
import java.math.BigDecimal
import java.sql.Types
import java.time.Instant
import java.time.LocalDate

/** A business trip with its settlement (ADR-0019); amounts in the currency of the country. */
data class TripResponse(
    val id: Long,
    val number: String,
    val travellerUserId: Int,
    val travellerName: String,
    val travellerDepartment: String?,
    val legalEntityId: Int,
    val legalEntityName: String,
    /** CLIENT_VISIT, TRADE_FAIR, PROJECT_SITE or OTHER. */
    val purpose: String,
    val clientId: Long?,
    val clientName: String?,
    val projectId: Long?,
    val projectName: String?,
    val eventName: String?,
    val description: String,
    val destination: String,
    val country: String,
    val countryNamePl: String?,
    val countryNameEn: String?,
    val startsAt: Instant,
    val endsAt: Instant,
    val transport: String,
    val carId: Int?,
    val carPlate: String?,
    val vehicle: String?,
    val kilometres: Int?,
    val breakfasts: Int,
    val lunches: Int,
    val dinners: Int,
    val lumpNights: Int,
    val localTransport: Boolean,
    val advance: BigDecimal,
    /** PLANNED, SUBMITTED, RETURNED, APPROVED, PAID or CANCELLED. */
    val status: String,
    val submittedAt: Instant?,
    val decidedBy: Int?,
    val decidedByName: String?,
    val decidedAt: Instant?,
    val decisionNote: String?,
    val paidAt: Instant?,
    val currency: String,
    val dietRate: BigDecimal,
    val diets: BigDecimal,
    val dietAmount: BigDecimal,
    val mealDeduction: BigDecimal,
    val lumpAmount: BigDecimal,
    val mileageAmount: BigDecimal,
    val expensesAmount: BigDecimal,
    val total: BigDecimal,
    /** Total less the advance; negative: the traveller gives money back. */
    val toPay: BigDecimal,
    val hotelOverLimit: Boolean,
    val createdBy: Int,
    val createdAt: Instant,
    val updatedAt: Instant,
    val rowVersion: String,
)

data class TripRequest(
    /** Someone else's trip - managers only; the actor's when empty. Ignored on update. */
    val travellerUserId: Int?,
    @field:NotBlank @field:Pattern(regexp = "CLIENT_VISIT|TRADE_FAIR|PROJECT_SITE|OTHER") val purpose: String?,
    val clientId: Long?,
    val projectId: Long?,
    @field:Size(max = 200) val eventName: String?,
    @field:Size(max = 1000) val description: String?,
    @field:NotBlank @field:Size(max = 120) val destination: String?,
    @field:NotBlank @field:Size(min = 2, max = 2) val country: String?,
    @field:NotNull val startsAt: Instant?,
    @field:NotNull val endsAt: Instant?,
    @field:NotBlank val transport: String?,
    val carId: Int?,
    val vehicle: String?,
    val kilometres: Int?,
    val breakfasts: Int?,
    val lunches: Int?,
    val dinners: Int?,
    val lumpNights: Int?,
    val localTransport: Boolean?,
    val advance: BigDecimal?,
    val legalEntityId: Int?,
    /** Required to update; ignored on create. */
    @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

data class ExpenseResponse(
    val id: Long,
    val lineNo: Int,
    val category: String,
    val description: String,
    val spentOn: LocalDate,
    val document: String?,
    val amount: BigDecimal,
    val nights: Int?,
)

data class ExpenseRequest(
    @field:NotBlank val category: String?,
    @field:NotBlank @field:Size(max = 200) val description: String?,
    @field:NotNull val spentOn: LocalDate?,
    @field:Size(max = 60) val document: String?,
    @field:NotNull val amount: BigDecimal?,
    val nights: Int?,
)

data class ExpensesRequest(
    @field:NotNull @field:Size(max = 50) val items: List<@Valid ExpenseRequest>?,
    @field:NotBlank @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

data class TripStatusRequest(
    @field:NotBlank @field:Pattern(regexp = "SUBMIT|APPROVE|RETURN|PAY|CANCEL") val action: String?,
    @field:Size(max = 400) val note: String?,
    @field:NotBlank @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

/** A rate in force: per diem and hotel limit of a country, or the mileage of a vehicle. */
data class TripRateResponse(
    val kind: String,
    val code: String,
    val namePl: String,
    val nameEn: String,
    val currency: String,
    val amount: BigDecimal,
    val hotelLimit: BigDecimal?,
    val validFrom: LocalDate,
)

data class TripFilter(
    val scope: String,
    val status: String?,
    val purpose: String?,
    val travellerUserId: Int?,
    val from: LocalDate?,
    val to: LocalDate?,
)

/** Business trips (ADR-0019): one `EXEC app.trip_*` per method. */
@Repository
class TripRepository(private val jdbc: JdbcClient, private val json: JsonMapper) {
    private val row = RowMapper { rs, _ ->
        TripResponse(
            id = rs.getLong("id"), number = rs.getString("number"), travellerUserId = rs.getInt("traveller_user_id"),
            travellerName = rs.getString("traveller_name"), travellerDepartment = rs.getString("traveller_department"),
            legalEntityId = rs.getInt("legal_entity_id"), legalEntityName = rs.getString("legal_entity_name"),
            purpose = rs.getString("purpose"), clientId = rs.getLongOrNull("client_id"), clientName = rs.getString("client_name"),
            projectId = rs.getLongOrNull("project_id"), projectName = rs.getString("project_name"), eventName = rs.getString("event_name"),
            description = rs.getString("description"), destination = rs.getString("destination"), country = rs.getString("country"),
            countryNamePl = rs.getString("country_name_pl"), countryNameEn = rs.getString("country_name_en"),
            startsAt = rs.getInstant("starts_at"), endsAt = rs.getInstant("ends_at"), transport = rs.getString("transport"),
            carId = rs.getIntOrNull("car_id"), carPlate = rs.getString("car_plate"), vehicle = rs.getString("vehicle"),
            kilometres = rs.getIntOrNull("kilometres"), breakfasts = rs.getInt("breakfasts"), lunches = rs.getInt("lunches"),
            dinners = rs.getInt("dinners"), lumpNights = rs.getInt("lump_nights"), localTransport = rs.getBoolean("local_transport"),
            advance = rs.getBigDecimal("advance"), status = rs.getString("status"), submittedAt = rs.getInstantOrNull("submitted_at"),
            decidedBy = rs.getIntOrNull("decided_by"), decidedByName = rs.getString("decided_by_name"),
            decidedAt = rs.getInstantOrNull("decided_at"), decisionNote = rs.getString("decision_note"),
            paidAt = rs.getInstantOrNull("paid_at"), currency = rs.getString("currency"), dietRate = rs.getBigDecimal("diet_rate"),
            diets = rs.getBigDecimal("diets"), dietAmount = rs.getBigDecimal("diet_amount"),
            mealDeduction = rs.getBigDecimal("meal_deduction"), lumpAmount = rs.getBigDecimal("lump_amount"),
            mileageAmount = rs.getBigDecimal("mileage_amount"), expensesAmount = rs.getBigDecimal("expenses_amount"),
            total = rs.getBigDecimal("total"), toPay = rs.getBigDecimal("to_pay"), hotelOverLimit = rs.getBoolean("hotel_over_limit"),
            createdBy = rs.getInt("created_by"), createdAt = rs.getInstant("created_at"), updatedAt = rs.getInstant("updated_at"),
            rowVersion = rs.getRowVersion(),
        )
    }

    private fun JdbcClient.StatementSpec.filter(f: TripFilter) = this
        .param("scope", f.scope, Types.VARCHAR)
        .param("status", f.status, Types.VARCHAR)
        .param("purpose", f.purpose, Types.VARCHAR)
        .param("traveller", f.travellerUserId, Types.INTEGER)
        .param("from", f.from, Types.DATE)
        .param("to", f.to, Types.DATE)

    private val filterArgs = "@scope = :scope, @status = :status, @purpose = :purpose, @traveller_user_id = :traveller, @from = :from, @to = :to"

    fun list(actorId: Int, f: TripFilter, afterStart: Instant?, afterId: Long?, size: Int): List<TripResponse> =
        jdbc.sql("EXEC app.trip_list @actor_id = :actorId, $filterArgs, @after_start = :afterStart, @after_id = :afterId, @page_size = :size")
            .param("actorId", actorId, Types.INTEGER)
            .filter(f)
            .param("afterStart", afterStart?.toUtcLocalDateTime(), Types.TIMESTAMP)
            .param("afterId", afterId, Types.BIGINT)
            .param("size", size, Types.INTEGER)
            .query(row)
            .list()

    fun count(actorId: Int, f: TripFilter): Long =
        jdbc.sql("EXEC app.trip_count @actor_id = :actorId, $filterArgs")
            .param("actorId", actorId, Types.INTEGER).filter(f).query { rs, _ -> rs.getLong("total") }.single()

    fun get(actorId: Int, id: Long): TripResponse =
        jdbc.sql("EXEC app.trip_get @actor_id = :actorId, @trip_id = :id").param("actorId", actorId).param("id", id).query(row).single()

    private val fieldArgs = "@purpose = :purpose, @client_id = :clientId, @project_id = :projectId, @event_name = :eventName, " +
        "@description = :description, @destination = :destination, @country = :country, @starts_at = :startsAt, " +
        "@ends_at = :endsAt, @transport = :transport, @car_id = :carId, @vehicle = :vehicle, @kilometres = :km, " +
        "@breakfasts = :breakfasts, @lunches = :lunches, @dinners = :dinners, @lump_nights = :lumpNights, " +
        "@local_transport = :localTransport, @advance = :advance, @legal_entity_id = :entity"

    private fun JdbcClient.StatementSpec.fields(b: TripRequest) = this
        .param("purpose", b.purpose, Types.VARCHAR)
        .param("clientId", b.clientId, Types.BIGINT)
        .param("projectId", b.projectId, Types.BIGINT)
        .param("eventName", b.eventName, Types.NVARCHAR)
        .param("description", b.description, Types.NVARCHAR)
        .param("destination", b.destination, Types.NVARCHAR)
        .param("country", b.country?.uppercase(), Types.CHAR)
        .param("startsAt", b.startsAt?.toUtcLocalDateTime(), Types.TIMESTAMP)
        .param("endsAt", b.endsAt?.toUtcLocalDateTime(), Types.TIMESTAMP)
        .param("transport", b.transport, Types.VARCHAR)
        .param("carId", b.carId, Types.INTEGER)
        .param("vehicle", b.vehicle, Types.VARCHAR)
        .param("km", b.kilometres, Types.INTEGER)
        .param("breakfasts", b.breakfasts ?: 0, Types.INTEGER)
        .param("lunches", b.lunches ?: 0, Types.INTEGER)
        .param("dinners", b.dinners ?: 0, Types.INTEGER)
        .param("lumpNights", b.lumpNights ?: 0, Types.INTEGER)
        .param("localTransport", b.localTransport ?: false, Types.BIT)
        .param("advance", b.advance ?: BigDecimal.ZERO, Types.DECIMAL)
        .param("entity", b.legalEntityId, Types.INTEGER)

    fun create(actorId: Int, b: TripRequest): TripResponse =
        jdbc.sql("EXEC app.trip_create @actor_id = :actorId, @traveller_user_id = :traveller, $fieldArgs")
            .param("actorId", actorId, Types.INTEGER).param("traveller", b.travellerUserId, Types.INTEGER).fields(b).query(row).single()

    fun update(actorId: Int, id: Long, b: TripRequest): TripResponse =
        jdbc.sql("EXEC app.trip_update @actor_id = :actorId, @trip_id = :id, $fieldArgs, @row_version = :rowVersion")
            .param("actorId", actorId, Types.INTEGER).param("id", id, Types.BIGINT).fields(b)
            .param("rowVersion", b.rowVersion?.let(RowVersion::parse), Types.BINARY).query(row).single()

    fun expenses(actorId: Int, id: Long): List<ExpenseResponse> =
        jdbc.sql("EXEC app.trip_expense_list @actor_id = :actorId, @trip_id = :id").param("actorId", actorId).param("id", id)
            .query { rs, _ ->
                ExpenseResponse(
                    rs.getLong("id"), rs.getInt("line_no"), rs.getString("category"), rs.getString("description"),
                    rs.getLocalDate("spent_on"), rs.getString("document"), rs.getBigDecimal("amount"), rs.getIntOrNull("nights"),
                )
            }
            .list()

    fun saveExpenses(actorId: Int, id: Long, b: ExpensesRequest): TripResponse =
        jdbc.sql("EXEC app.trip_expenses_save @actor_id = :actorId, @trip_id = :id, @items = :items, @row_version = :rowVersion")
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .param("items", json.writeValueAsString(b.items), Types.NVARCHAR)
            .param("rowVersion", RowVersion.parse(b.rowVersion!!), Types.BINARY)
            .query(row)
            .single()

    fun changeStatus(actorId: Int, id: Long, b: TripStatusRequest): TripResponse =
        jdbc.sql("EXEC app.trip_change_status @actor_id = :actorId, @trip_id = :id, @action = :action, @note = :note, @row_version = :rowVersion")
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .param("action", b.action, Types.VARCHAR)
            .param("note", b.note, Types.NVARCHAR)
            .param("rowVersion", RowVersion.parse(b.rowVersion!!), Types.BINARY)
            .query(row)
            .single()

    fun rates(actorId: Int): List<TripRateResponse> =
        jdbc.sql("EXEC app.trip_rate_list @actor_id = :actorId").param("actorId", actorId)
            .query { rs, _ ->
                TripRateResponse(
                    rs.getString("kind"), rs.getString("code"), rs.getString("name_pl"), rs.getString("name_en"), rs.getString("currency"),
                    rs.getBigDecimal("amount"), rs.getBigDecimal("hotel_limit"), rs.getLocalDate("valid_from"),
                )
            }
            .list()
}

/** Business trips and their settlement (ADR-0019): everybody their own, managers all and the approvals. */
@Tag(name = "Business trips")
@RestController
@RequestMapping("/api/trips")
class TripController(private val trips: TripRepository) {

    @Operation(summary = "Trips, newest first. scope MINE, TO_APPROVE (managers) or ALL (managers).")
    @GetMapping
    fun listTrips(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(defaultValue = "MINE") scope: String,
        @RequestParam(required = false) status: String?,
        @RequestParam(required = false) purpose: String?,
        @RequestParam(required = false) travellerUserId: Int?,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) from: LocalDate?,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) to: LocalDate?,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "50") @Min(1) @Max(200) size: Int,
    ): PageResponse<TripResponse> {
        val after = Cursor.decode(cursor, 2)
        val afterStart = after?.let { runCatching { Instant.parse(it[0]) }.getOrElse { throw InvalidCursorException("Invalid cursor.") } }
        val afterId = after?.let { it[1].toLongOrNull() ?: throw InvalidCursorException("Invalid cursor.") }
        val rows = trips.list(actor.id, TripFilter(scope, status, purpose, travellerUserId, from, to), afterStart, afterId, size)
        return Cursor.page(rows, size) { Cursor.encode(it.startsAt.toString(), it.id) }
    }

    @Operation(summary = "The number of trips for the same filters. Call it only on request.")
    @GetMapping("/count")
    fun countTrips(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(defaultValue = "MINE") scope: String,
        @RequestParam(required = false) status: String?,
        @RequestParam(required = false) purpose: String?,
        @RequestParam(required = false) travellerUserId: Int?,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) from: LocalDate?,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) to: LocalDate?,
    ): TotalResponse = TotalResponse(trips.count(actor.id, TripFilter(scope, status, purpose, travellerUserId, from, to)))

    @Operation(summary = "The rates in force: per diem and hotel limit per country, mileage per vehicle.")
    @GetMapping("/rates")
    fun listTripRates(@AuthenticationPrincipal actor: CrmUserDetails): List<TripRateResponse> = trips.rates(actor.id)

    @Operation(summary = "One trip with its settlement.")
    @GetMapping("/{id}")
    fun getTrip(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Long): TripResponse = trips.get(actor.id, id)

    @Operation(summary = "Plan a trip (for somebody else: managers).")
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    fun createTrip(@AuthenticationPrincipal actor: CrmUserDetails, @Valid @RequestBody body: TripRequest): TripResponse =
        trips.create(actor.id, body)

    @Operation(summary = "Change a planned or returned trip. rowVersion required.")
    @PutMapping("/{id}")
    fun updateTrip(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Long, @Valid @RequestBody body: TripRequest): TripResponse =
        trips.update(actor.id, id, body)

    @Operation(summary = "The trip's expenses.")
    @GetMapping("/{id}/expenses")
    fun listTripExpenses(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Long): List<ExpenseResponse> =
        trips.expenses(actor.id, id)

    @Operation(summary = "Replace the trip's expenses (at most 50). rowVersion required.")
    @PutMapping("/{id}/expenses")
    fun saveTripExpenses(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: ExpensesRequest,
    ): TripResponse = trips.saveExpenses(actor.id, id, body)

    @Operation(summary = "SUBMIT (after the trip), APPROVE / RETURN with a note (managers, not their own), PAY, CANCEL.")
    @PostMapping("/{id}/status")
    fun changeTripStatus(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: TripStatusRequest,
    ): TripResponse = trips.changeStatus(actor.id, id, body)
}
