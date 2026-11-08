package crm.fleet

import crm.shared.RowVersion
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate

/** A car of the fleet (ADR-0018), with today's availability and holder. Money only for managers and administrators. */
data class CarResponse(
    val id: Int,
    val name: String,
    val make: String?,
    val productionYear: Int?,
    val plate: String,
    val vin: String?,
    val notes: String?,
    val legalEntityId: Int,
    val legalEntityName: String,
    val status: String,
    val statusNamePl: String,
    val statusNameEn: String,
    val statusSince: LocalDate,
    val repairShopId: Int?,
    val repairShopName: String?,
    /** UNKNOWN, PAID or LEASING. */
    val financing: String,
    val purchaseDate: LocalDate?,
    val leasingId: Int?,
    val leasingName: String?,
    val instalment: BigDecimal?,
    val currency: String?,
    val leaseStart: LocalDate?,
    val leaseMonths: Int?,
    val leaseEnd: LocalDate?,
    val contractNo: String?,
    val inspectionDue: LocalDate?,
    val insuranceDue: LocalDate?,
    /** FREE, HANDED_OVER or OVERDUE, for today in Warsaw. */
    val availability: String,
    /** The current handover, else the next planned one. */
    val handoverId: Long?,
    val holderUserId: Int?,
    val holderName: String?,
    val holderFrom: LocalDate?,
    val holderUntil: LocalDate?,
    val holderPlanned: Boolean,
    val createdAt: Instant,
    val updatedAt: Instant,
    val rowVersion: String,
)

data class CarRequest(
    @field:NotBlank @field:Size(max = 100) val name: String?,
    @field:Size(max = 60) val make: String?,
    val productionYear: Int?,
    @field:NotBlank @field:Size(max = 15) val plate: String?,
    @field:Size(max = 17) val vin: String?,
    @field:Size(max = 1000) val notes: String?,
    @field:NotNull val legalEntityId: Int?,
    val inspectionDue: LocalDate?,
    val insuranceDue: LocalDate?,
    /** Required to correct a VIN already given (administrators). */
    @field:Size(max = 400) val vinReason: String?,
    /** Required to update; ignored on create. */
    @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

data class FinancingRequest(
    @field:NotBlank @field:Pattern(regexp = "UNKNOWN|PAID|LEASING") val financing: String?,
    val purchaseDate: LocalDate?,
    val leasingId: Int?,
    val instalment: BigDecimal?,
    @field:Size(max = 3) val currency: String?,
    val leaseStart: LocalDate?,
    val leaseMonths: Int?,
    @field:Size(max = 60) val contractNo: String?,
    @field:NotBlank @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

data class StatusRequest(
    @field:NotBlank val status: String?,
    val effectiveOn: LocalDate?,
    val repairShopId: Int?,
    @field:Size(max = 400) val note: String?,
    @field:NotBlank @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

data class CarStatusResponse(val status: String, val needsShop: Boolean, val namePl: String, val nameEn: String)

data class StatusHistoryResponse(
    val id: Long,
    val status: String,
    val statusNamePl: String,
    val statusNameEn: String,
    val effectiveOn: LocalDate,
    val repairShop: String?,
    val note: String?,
    val changedBy: Int,
    val changedByName: String,
    val changedAt: Instant,
)

/** Who has a car from which day to which day (ADR-0018). */
data class HandoverResponse(
    val id: Long,
    val carId: Int,
    val carName: String,
    val plate: String,
    val holderUserId: Int,
    val holderName: String,
    val issueDate: LocalDate,
    val plannedReturn: LocalDate?,
    val issueMileage: Int,
    val issueFuel: Int,
    val notes: String?,
    val issuedBy: Int,
    val issuedByName: String,
    val issuedAt: Instant,
    val returnedOn: LocalDate?,
    val returnMileage: Int?,
    val returnFuel: Int?,
    val cancelledAt: Instant?,
    val cancelReason: String?,
    /** CANCELLED, RETURNED, PLANNED, OVERDUE or CURRENT, for today in Warsaw. */
    val state: String,
    val rowVersion: String,
    /** On a new handover: REPAIR_SHOP:<name> when the car is at a repair shop. */
    val warning: String? = null,
)

data class HandoverRequest(
    @field:NotNull val holderUserId: Int?,
    @field:NotNull val issueDate: LocalDate?,
    val plannedReturn: LocalDate?,
    @field:NotNull val issueMileage: Int?,
    @field:NotNull val issueFuel: Int?,
    @field:Size(max = 1000) val notes: String?,
)

data class ReturnRequest(
    @field:NotNull val returnedOn: LocalDate?,
    @field:NotNull val returnMileage: Int?,
    @field:NotNull val returnFuel: Int?,
    @field:NotBlank @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

data class ChangeHandoverRequest(
    val plannedReturn: LocalDate?,
    @field:Size(max = 1000) val notes: String?,
    @field:NotBlank @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

data class CancelHandoverRequest(
    @field:NotBlank @field:Size(max = 400) val reason: String?,
    @field:NotBlank @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

data class RowVersionRequest(@field:NotBlank @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?)

/** A repair shop or a leasing company. */
data class PartnerResponse(
    val id: Int,
    val kind: String,
    val name: String,
    val phone: String?,
    val note: String?,
    val hidden: Boolean,
    val cars: Int,
    val rowVersion: String,
)

data class PartnerRequest(
    @field:NotBlank @field:Pattern(regexp = "REPAIR_SHOP|LEASING") val kind: String?,
    @field:NotBlank @field:Size(max = 120) val name: String?,
    @field:Size(max = 40) val phone: String?,
    @field:Size(max = 400) val note: String?,
    val hidden: Boolean?,
    @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)
