package crm.offers

import jakarta.validation.constraints.NotBlank
import org.springframework.boot.context.properties.ConfigurationProperties
import org.springframework.validation.annotation.Validated

/**
 * The company on the offer PDFs (ADR-0013), env only: CRM_OFFER_COMPANY_NAME (Halycon Inc.), _ADDRESS, _PHONE, _EMAIL,
 * _WEBSITE, _TAX_ID. The phone and e-mail close an offer whose author is not a salesperson.
 */
@Validated
@ConfigurationProperties("crm.offer")
data class OfferProperties(
    @field:NotBlank val companyName: String = "Halycon Inc.",
    val companyAddress: String = "ul. Obsydianowa 12, 00-950 Warszawa",
    val companyPhone: String = "+48 22 100 20 30",
    val companyEmail: String = "oferty@halycon.example",
    val companyWebsite: String = "halycon.example",
    val companyTaxId: String = "NIP 525-000-00-00",
)
