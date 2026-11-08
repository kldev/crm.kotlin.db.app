package crm.offers

import jakarta.validation.Valid
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import crm.shared.RowVersion
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate

const val OFFER_STATUSES = "DRAFT|SENT|ACCEPTED|REJECTED"

data class OfferTemplateResponse(
    val key: String,
    val namePl: String,
    val nameEn: String,
    val titlePl: String,
    val titleEn: String,
    val validityDays: Int,
    val itemCount: Int,
)

/** An offer with its client, author (whose contact closes the PDF when they sell) and totals. */
data class OfferResponse(
    val id: Long,
    val number: String,
    val clientId: Long,
    val clientName: String,
    val clientNip: String?,
    val clientCity: String?,
    val clientEmail: String?,
    val templateKey: String,
    val templateNamePl: String,
    val templateNameEn: String,
    val title: String,
    val intro: String,
    val terms: String,
    val currency: String,
    val validUntil: LocalDate,
    /** DRAFT, SENT, ACCEPTED or REJECTED. */
    val status: String,
    val authorUserId: Int,
    val authorName: String,
    val authorRole: String,
    val authorJobTitle: String?,
    val authorPhone: String?,
    val authorEmail: String?,
    val sentAt: Instant?,
    val decidedAt: Instant?,
    val createdAt: Instant,
    val updatedAt: Instant,
    val itemCount: Int,
    val totalNet: BigDecimal,
    val totalVat: BigDecimal,
    val totalGross: BigDecimal,
    val rowVersion: String,
)

data class OfferItemResponse(
    val lineNo: Int,
    val description: String,
    val unit: String,
    val quantity: BigDecimal,
    val unitPrice: BigDecimal,
    val vatRate: Int,
    val net: BigDecimal,
    val vat: BigDecimal,
    val gross: BigDecimal,
)

data class CreateOfferRequest(
    @field:NotNull val clientId: Long?,
    @field:NotBlank val templateKey: String?,
    @field:Size(max = 200) val title: String?,
    /** The language of the template texts copied into the offer: pl or en. */
    @field:Pattern(regexp = "pl|en") val lang: String? = "pl",
)

data class OfferItemRequest(
    @field:NotBlank @field:Size(max = 400) val description: String?,
    @field:NotBlank @field:Size(max = 20) val unit: String?,
    @field:NotNull val quantity: BigDecimal?,
    @field:NotNull val unitPrice: BigDecimal?,
    @field:NotNull val vatRate: Int?,
)

data class UpdateOfferRequest(
    @field:NotBlank @field:Size(max = 200) val title: String?,
    @field:Size(max = 2000) val intro: String?,
    @field:Size(max = 4000) val terms: String?,
    @field:NotBlank @field:Pattern(regexp = "PLN|EUR|USD") val currency: String?,
    @field:NotNull val validUntil: LocalDate?,
    @field:NotNull @field:Size(max = 100) val items: List<@Valid OfferItemRequest>?,
    @field:NotBlank @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

data class ChangeOfferStatusRequest(
    @field:NotBlank @field:Pattern(regexp = OFFER_STATUSES) val status: String?,
    @field:NotBlank @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

data class UserContactResponse(
    val id: Int,
    val displayName: String,
    val jobTitle: String?,
    val phone: String?,
    val email: String?,
)

data class UpdateContactRequest(
    @field:Size(max = 100) val jobTitle: String?,
    @field:Size(max = 30) val phone: String?,
    @field:Size(max = 254) val email: String?,
)
