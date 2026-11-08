package crm.fleet

import crm.auth.CrmUserDetails
import crm.shared.Cursor
import crm.shared.InvalidCursorException
import crm.shared.PageResponse
import crm.shared.RowVersion
import crm.shared.TotalResponse
import crm.shared.getInstant
import crm.shared.getInstantOrNull
import crm.shared.getIntOrNull
import crm.shared.getLongOrNull
import crm.shared.getLocalDate
import crm.shared.getRowVersion
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.validation.Valid
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import jakarta.validation.constraints.Pattern
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
import java.sql.ResultSet
import java.sql.Types
import java.time.LocalDate

data class CarFilter(
    val search: String?,
    val status: String?,
    val availability: String?,
    val legalEntityId: Int?,
    val repairShopId: Int?,
    val archived: Boolean,
    val dueSoon: Boolean,
)

private fun ResultSet.getLocalDateOrNull(column: String): LocalDate? = getObject(column, LocalDate::class.java)

/** The fleet (ADR-0018): one `EXEC app.car_*` / `app.fleet_*` per method. */
@Repository
class FleetRepository(private val jdbc: JdbcClient) {
    private val car = RowMapper { rs, _ ->
        CarResponse(
            id = rs.getInt("id"),
            name = rs.getString("name"),
            make = rs.getString("make"),
            productionYear = rs.getIntOrNull("production_year"),
            plate = rs.getString("plate"),
            vin = rs.getString("vin"),
            notes = rs.getString("notes"),
            legalEntityId = rs.getInt("legal_entity_id"),
            legalEntityName = rs.getString("legal_entity_name"),
            status = rs.getString("status"),
            statusNamePl = rs.getString("status_name_pl"),
            statusNameEn = rs.getString("status_name_en"),
            statusSince = rs.getLocalDate("status_since"),
            repairShopId = rs.getIntOrNull("repair_shop_id"),
            repairShopName = rs.getString("repair_shop_name"),
            financing = rs.getString("financing"),
            purchaseDate = rs.getLocalDateOrNull("purchase_date"),
            leasingId = rs.getIntOrNull("leasing_id"),
            leasingName = rs.getString("leasing_name"),
            instalment = rs.getBigDecimal("instalment"),
            currency = rs.getString("currency"),
            leaseStart = rs.getLocalDateOrNull("lease_start"),
            leaseMonths = rs.getIntOrNull("lease_months"),
            leaseEnd = rs.getLocalDateOrNull("lease_end"),
            contractNo = rs.getString("contract_no"),
            inspectionDue = rs.getLocalDateOrNull("inspection_due"),
            insuranceDue = rs.getLocalDateOrNull("insurance_due"),
            availability = rs.getString("availability"),
            handoverId = rs.getLongOrNull("handover_id"),
            holderUserId = rs.getIntOrNull("holder_user_id"),
            holderName = rs.getString("holder_name"),
            holderFrom = rs.getLocalDateOrNull("holder_from"),
            holderUntil = rs.getLocalDateOrNull("holder_until"),
            holderPlanned = rs.getBoolean("holder_planned"),
            createdAt = rs.getInstant("created_at"),
            updatedAt = rs.getInstant("updated_at"),
            rowVersion = rs.getRowVersion(),
        )
    }

    private val handover = RowMapper { rs, _ ->
        HandoverResponse(
            id = rs.getLong("id"),
            carId = rs.getInt("car_id"),
            carName = rs.getString("car_name"),
            plate = rs.getString("plate"),
            holderUserId = rs.getInt("holder_user_id"),
            holderName = rs.getString("holder_name"),
            issueDate = rs.getLocalDate("issue_date"),
            plannedReturn = rs.getLocalDateOrNull("planned_return"),
            issueMileage = rs.getInt("issue_mileage"),
            issueFuel = rs.getInt("issue_fuel"),
            notes = rs.getString("notes"),
            issuedBy = rs.getInt("issued_by"),
            issuedByName = rs.getString("issued_by_name"),
            issuedAt = rs.getInstant("issued_at"),
            returnedOn = rs.getLocalDateOrNull("returned_on"),
            returnMileage = rs.getIntOrNull("return_mileage"),
            returnFuel = rs.getIntOrNull("return_fuel"),
            cancelledAt = rs.getInstantOrNull("cancelled_at"),
            cancelReason = rs.getString("cancel_reason"),
            state = rs.getString("state"),
            rowVersion = rs.getRowVersion(),
            warning = runCatching { rs.getString("warning") }.getOrNull(),
        )
    }

    private val partner = RowMapper { rs, _ ->
        PartnerResponse(
            rs.getInt("id"), rs.getString("kind"), rs.getString("name"), rs.getString("phone"), rs.getString("note"),
            rs.getBoolean("is_hidden"), rs.getInt("cars"), rs.getRowVersion(),
        )
    }

    private fun JdbcClient.StatementSpec.filter(f: CarFilter) = this
        .param("search", f.search, Types.NVARCHAR)
        .param("status", f.status, Types.VARCHAR)
        .param("availability", f.availability, Types.VARCHAR)
        .param("legalEntityId", f.legalEntityId, Types.INTEGER)
        .param("repairShopId", f.repairShopId, Types.INTEGER)
        .param("archived", f.archived, Types.BIT)
        .param("dueSoon", f.dueSoon, Types.BIT)

    private val filterArgs = "@search = :search, @status = :status, @availability = :availability, " +
        "@legal_entity_id = :legalEntityId, @repair_shop_id = :repairShopId, @archived = :archived, @due_soon = :dueSoon"

    fun list(actorId: Int, f: CarFilter, afterName: String?, afterId: Int?, size: Int): List<CarResponse> =
        jdbc.sql("EXEC app.car_list @actor_id = :actorId, $filterArgs, @after_name = :afterName, @after_id = :afterId, @page_size = :size")
            .param("actorId", actorId, Types.INTEGER)
            .filter(f)
            .param("afterName", afterName, Types.NVARCHAR)
            .param("afterId", afterId, Types.INTEGER)
            .param("size", size, Types.INTEGER)
            .query(car)
            .list()

    fun count(actorId: Int, f: CarFilter): Long =
        jdbc.sql("EXEC app.car_count @actor_id = :actorId, $filterArgs")
            .param("actorId", actorId, Types.INTEGER).filter(f).query { rs, _ -> rs.getLong("total") }.single()

    fun get(actorId: Int, id: Int): CarResponse =
        jdbc.sql("EXEC app.car_get @actor_id = :actorId, @car_id = :id").param("actorId", actorId).param("id", id).query(car).single()

    fun save(actorId: Int, id: Int?, b: CarRequest): CarResponse =
        jdbc.sql(
            "EXEC app.car_save @actor_id = :actorId, @car_id = :id, @name = :name, @make = :make, " +
                "@production_year = :year, @plate = :plate, @vin = :vin, @notes = :notes, @legal_entity_id = :entity, " +
                "@inspection_due = :inspection, @insurance_due = :insurance, @vin_reason = :vinReason, @row_version = :rowVersion",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.INTEGER)
            .param("name", b.name, Types.NVARCHAR)
            .param("make", b.make, Types.NVARCHAR)
            .param("year", b.productionYear, Types.INTEGER)
            .param("plate", b.plate, Types.VARCHAR)
            .param("vin", b.vin, Types.VARCHAR)
            .param("notes", b.notes, Types.NVARCHAR)
            .param("entity", b.legalEntityId, Types.INTEGER)
            .param("inspection", b.inspectionDue, Types.DATE)
            .param("insurance", b.insuranceDue, Types.DATE)
            .param("vinReason", b.vinReason, Types.NVARCHAR)
            .param("rowVersion", b.rowVersion?.let(RowVersion::parse), Types.BINARY)
            .query(car)
            .single()

    fun setFinancing(actorId: Int, id: Int, b: FinancingRequest): CarResponse =
        jdbc.sql(
            "EXEC app.car_set_financing @actor_id = :actorId, @car_id = :id, @financing = :financing, " +
                "@purchase_date = :purchase, @leasing_id = :leasing, @instalment = :instalment, @currency = :currency, " +
                "@lease_start = :start, @lease_months = :months, @contract_no = :contract, @row_version = :rowVersion",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.INTEGER)
            .param("financing", b.financing, Types.VARCHAR)
            .param("purchase", b.purchaseDate, Types.DATE)
            .param("leasing", b.leasingId, Types.INTEGER)
            .param("instalment", b.instalment, Types.DECIMAL)
            .param("currency", b.currency, Types.CHAR)
            .param("start", b.leaseStart, Types.DATE)
            .param("months", b.leaseMonths, Types.INTEGER)
            .param("contract", b.contractNo, Types.NVARCHAR)
            .param("rowVersion", RowVersion.parse(b.rowVersion!!), Types.BINARY)
            .query(car)
            .single()

    fun changeStatus(actorId: Int, id: Int, b: StatusRequest): CarResponse =
        jdbc.sql(
            "EXEC app.car_change_status @actor_id = :actorId, @car_id = :id, @status = :status, @effective_on = :on, " +
                "@repair_shop_id = :shop, @note = :note, @row_version = :rowVersion",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.INTEGER)
            .param("status", b.status, Types.VARCHAR)
            .param("on", b.effectiveOn, Types.DATE)
            .param("shop", b.repairShopId, Types.INTEGER)
            .param("note", b.note, Types.NVARCHAR)
            .param("rowVersion", RowVersion.parse(b.rowVersion!!), Types.BINARY)
            .query(car)
            .single()

    fun delete(actorId: Int, id: Int, rowVersion: String) {
        jdbc.sql("EXEC app.car_delete @actor_id = :actorId, @car_id = :id, @row_version = :rowVersion")
            .param("actorId", actorId, Types.INTEGER).param("id", id, Types.INTEGER)
            .param("rowVersion", RowVersion.parse(rowVersion), Types.BINARY).update()
    }

    fun statusHistory(actorId: Int, id: Int): List<StatusHistoryResponse> =
        jdbc.sql("EXEC app.car_status_history @actor_id = :actorId, @car_id = :id")
            .param("actorId", actorId).param("id", id)
            .query { rs, _ ->
                StatusHistoryResponse(
                    rs.getLong("id"), rs.getString("status"), rs.getString("status_name_pl"), rs.getString("status_name_en"),
                    rs.getLocalDate("effective_on"), rs.getString("repair_shop"), rs.getString("note"), rs.getInt("changed_by"),
                    rs.getString("changed_by_name"), rs.getInstant("changed_at"),
                )
            }
            .list()

    fun statuses(actorId: Int): List<CarStatusResponse> =
        jdbc.sql("EXEC app.car_status_list @actor_id = :actorId").param("actorId", actorId)
            .query { rs, _ -> CarStatusResponse(rs.getString("status"), rs.getBoolean("needs_shop"), rs.getString("name_pl"), rs.getString("name_en")) }
            .list()

    fun makes(actorId: Int): List<String> =
        jdbc.sql("EXEC app.car_make_list @actor_id = :actorId").param("actorId", actorId).query { rs, _ -> rs.getString("make") }.list()

    fun handovers(actorId: Int, carId: Int): List<HandoverResponse> =
        jdbc.sql("EXEC app.car_handover_list @actor_id = :actorId, @car_id = :id").param("actorId", actorId).param("id", carId).query(handover).list()

    fun myHandovers(actorId: Int): List<HandoverResponse> =
        jdbc.sql("EXEC app.car_my @actor_id = :actorId").param("actorId", actorId).query(handover).list()

    fun handOver(actorId: Int, carId: Int, b: HandoverRequest): HandoverResponse =
        jdbc.sql(
            "EXEC app.car_handover_create @actor_id = :actorId, @car_id = :carId, @holder_user_id = :holder, " +
                "@issue_date = :issue, @planned_return = :planned, @issue_mileage = :mileage, @issue_fuel = :fuel, @notes = :notes",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("carId", carId, Types.INTEGER)
            .param("holder", b.holderUserId, Types.INTEGER)
            .param("issue", b.issueDate, Types.DATE)
            .param("planned", b.plannedReturn, Types.DATE)
            .param("mileage", b.issueMileage, Types.INTEGER)
            .param("fuel", b.issueFuel, Types.INTEGER)
            .param("notes", b.notes, Types.NVARCHAR)
            .query(handover)
            .single()

    fun takeBack(actorId: Int, id: Long, b: ReturnRequest): HandoverResponse =
        jdbc.sql(
            "EXEC app.car_handover_return @actor_id = :actorId, @handover_id = :id, @returned_on = :on, " +
                "@return_mileage = :mileage, @return_fuel = :fuel, @row_version = :rowVersion",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .param("on", b.returnedOn, Types.DATE)
            .param("mileage", b.returnMileage, Types.INTEGER)
            .param("fuel", b.returnFuel, Types.INTEGER)
            .param("rowVersion", RowVersion.parse(b.rowVersion!!), Types.BINARY)
            .query(handover)
            .single()

    fun undoReturn(actorId: Int, id: Long, rowVersion: String): HandoverResponse =
        jdbc.sql("EXEC app.car_handover_undo_return @actor_id = :actorId, @handover_id = :id, @row_version = :rowVersion")
            .param("actorId", actorId, Types.INTEGER).param("id", id, Types.BIGINT)
            .param("rowVersion", RowVersion.parse(rowVersion), Types.BINARY).query(handover).single()

    fun change(actorId: Int, id: Long, b: ChangeHandoverRequest): HandoverResponse =
        jdbc.sql(
            "EXEC app.car_handover_change @actor_id = :actorId, @handover_id = :id, @planned_return = :planned, " +
                "@notes = :notes, @row_version = :rowVersion",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .param("planned", b.plannedReturn, Types.DATE)
            .param("notes", b.notes, Types.NVARCHAR)
            .param("rowVersion", RowVersion.parse(b.rowVersion!!), Types.BINARY)
            .query(handover)
            .single()

    fun cancel(actorId: Int, id: Long, b: CancelHandoverRequest): HandoverResponse =
        jdbc.sql("EXEC app.car_handover_cancel @actor_id = :actorId, @handover_id = :id, @reason = :reason, @row_version = :rowVersion")
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .param("reason", b.reason, Types.NVARCHAR)
            .param("rowVersion", RowVersion.parse(b.rowVersion!!), Types.BINARY)
            .query(handover)
            .single()

    fun partners(actorId: Int, kind: String?): List<PartnerResponse> =
        jdbc.sql("EXEC app.fleet_partner_list @actor_id = :actorId, @kind = :kind")
            .param("actorId", actorId, Types.INTEGER).param("kind", kind, Types.VARCHAR).query(partner).list()

    fun savePartner(actorId: Int, id: Int?, b: PartnerRequest): PartnerResponse =
        jdbc.sql(
            "EXEC app.fleet_partner_save @actor_id = :actorId, @partner_id = :id, @kind = :kind, @name = :name, " +
                "@phone = :phone, @note = :note, @hidden = :hidden, @row_version = :rowVersion",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.INTEGER)
            .param("kind", b.kind, Types.VARCHAR)
            .param("name", b.name, Types.NVARCHAR)
            .param("phone", b.phone, Types.VARCHAR)
            .param("note", b.note, Types.NVARCHAR)
            .param("hidden", b.hidden ?: false, Types.BIT)
            .param("rowVersion", b.rowVersion?.let(RowVersion::parse), Types.BINARY)
            .query(partner)
            .single()
}

/** The fleet (ADR-0018), after Ambit System's: everybody reads it, managers and administrators run it. */
@Tag(name = "Fleet")
@RestController
@RequestMapping("/api/fleet")
class FleetController(private val fleet: FleetRepository) {

    @Operation(summary = "Cars by name. search: name, plate (however spaced) or make; availability FREE, HANDED_OVER, OVERDUE; dueSoon: inspection or insurance within 30 days.")
    @GetMapping("/cars")
    fun listCars(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(required = false) search: String?,
        @RequestParam(required = false) status: String?,
        @RequestParam(required = false) availability: String?,
        @RequestParam(required = false) legalEntityId: Int?,
        @RequestParam(required = false) repairShopId: Int?,
        @RequestParam(defaultValue = "false") archived: Boolean,
        @RequestParam(defaultValue = "false") dueSoon: Boolean,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "50") @Min(1) @Max(200) size: Int,
    ): PageResponse<CarResponse> {
        val after = Cursor.decode(cursor, 2)
        val afterId = after?.let { it[1].toIntOrNull() ?: throw InvalidCursorException("Invalid cursor.") }
        val rows = fleet.list(actor.id, CarFilter(search, status, availability, legalEntityId, repairShopId, archived, dueSoon), after?.get(0), afterId, size)
        return Cursor.page(rows, size) { Cursor.encode(it.name, it.id) }
    }

    @Operation(summary = "The number of cars for the same filters. Call it only on request.")
    @GetMapping("/cars/count")
    fun countCars(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(required = false) search: String?,
        @RequestParam(required = false) status: String?,
        @RequestParam(required = false) availability: String?,
        @RequestParam(required = false) legalEntityId: Int?,
        @RequestParam(required = false) repairShopId: Int?,
        @RequestParam(defaultValue = "false") archived: Boolean,
        @RequestParam(defaultValue = "false") dueSoon: Boolean,
    ): TotalResponse = TotalResponse(fleet.count(actor.id, CarFilter(search, status, availability, legalEntityId, repairShopId, archived, dueSoon)))

    @Operation(summary = "One car.")
    @GetMapping("/cars/{id}")
    fun getCar(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Int): CarResponse = fleet.get(actor.id, id)

    @Operation(summary = "Add a car (managers).")
    @PostMapping("/cars")
    @ResponseStatus(HttpStatus.CREATED)
    fun createCar(@AuthenticationPrincipal actor: CrmUserDetails, @Valid @RequestBody body: CarRequest): CarResponse =
        fleet.save(actor.id, null, body)

    @Operation(summary = "Change a car's data (managers); a VIN once given is corrected by an administrator with a reason.")
    @PutMapping("/cars/{id}")
    fun updateCar(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Int, @Valid @RequestBody body: CarRequest): CarResponse =
        fleet.save(actor.id, id, body)

    @Operation(summary = "How the car is financed (managers).")
    @PutMapping("/cars/{id}/financing")
    fun setCarFinancing(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Int,
        @Valid @RequestBody body: FinancingRequest,
    ): CarResponse = fleet.setFinancing(actor.id, id, body)

    @Operation(summary = "Change the car's status from a day (managers).")
    @PostMapping("/cars/{id}/status")
    fun changeCarStatus(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Int,
        @Valid @RequestBody body: StatusRequest,
    ): CarResponse = fleet.changeStatus(actor.id, id, body)

    @Operation(summary = "Delete a car never handed over (managers); otherwise archive it.")
    @DeleteMapping("/cars/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun deleteCar(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Int,
        @RequestParam @Pattern(regexp = RowVersion.PATTERN) rowVersion: String,
    ) = fleet.delete(actor.id, id, rowVersion)

    @Operation(summary = "The car's statuses, newest first.")
    @GetMapping("/cars/{id}/status-history")
    fun carStatusHistory(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Int): List<StatusHistoryResponse> =
        fleet.statusHistory(actor.id, id)

    @Operation(summary = "The car's handovers, newest first.")
    @GetMapping("/cars/{id}/handovers")
    fun carHandovers(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Int): List<HandoverResponse> =
        fleet.handovers(actor.id, id)

    @Operation(summary = "Hand the car over to a person (managers); no overlaps per car or per person.")
    @PostMapping("/cars/{id}/handovers")
    @ResponseStatus(HttpStatus.CREATED)
    fun handOverCar(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Int,
        @Valid @RequestBody body: HandoverRequest,
    ): HandoverResponse = fleet.handOver(actor.id, id, body)

    @Operation(summary = "Take the car back.")
    @PostMapping("/handovers/{id}/return")
    fun returnCar(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Long, @Valid @RequestBody body: ReturnRequest): HandoverResponse =
        fleet.takeBack(actor.id, id, body)

    @Operation(summary = "Undo a return on its own day.")
    @PostMapping("/handovers/{id}/undo-return")
    fun undoCarReturn(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: RowVersionRequest,
    ): HandoverResponse = fleet.undoReturn(actor.id, id, body.rowVersion!!)

    @Operation(summary = "Move the planned return or change the notes of a live handover.")
    @PutMapping("/handovers/{id}")
    fun changeHandover(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: ChangeHandoverRequest,
    ): HandoverResponse = fleet.change(actor.id, id, body)

    @Operation(summary = "Cancel a handover entered by mistake, with a reason.")
    @PostMapping("/handovers/{id}/cancel")
    fun cancelHandover(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: CancelHandoverRequest,
    ): HandoverResponse = fleet.cancel(actor.id, id, body)

    @Operation(summary = "My car: my live handovers and those returned in the last 30 days.")
    @GetMapping("/my")
    fun myCars(@AuthenticationPrincipal actor: CrmUserDetails): List<HandoverResponse> = fleet.myHandovers(actor.id)

    @Operation(summary = "The car statuses in order.")
    @GetMapping("/statuses")
    fun listCarStatuses(@AuthenticationPrincipal actor: CrmUserDetails): List<CarStatusResponse> = fleet.statuses(actor.id)

    @Operation(summary = "Makes to suggest.")
    @GetMapping("/makes")
    fun listCarMakes(@AuthenticationPrincipal actor: CrmUserDetails): List<String> = fleet.makes(actor.id)

    @Operation(summary = "Repair shops and leasing companies.")
    @GetMapping("/partners")
    fun listFleetPartners(@AuthenticationPrincipal actor: CrmUserDetails, @RequestParam(required = false) kind: String?): List<PartnerResponse> =
        fleet.partners(actor.id, kind)

    @Operation(summary = "Add a repair shop or a leasing company (managers).")
    @PostMapping("/partners")
    @ResponseStatus(HttpStatus.CREATED)
    fun createFleetPartner(@AuthenticationPrincipal actor: CrmUserDetails, @Valid @RequestBody body: PartnerRequest): PartnerResponse =
        fleet.savePartner(actor.id, null, body)

    @Operation(summary = "Change, hide or show a repair shop or a leasing company (managers).")
    @PutMapping("/partners/{id}")
    fun updateFleetPartner(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Int,
        @Valid @RequestBody body: PartnerRequest,
    ): PartnerResponse = fleet.savePartner(actor.id, id, body)
}
