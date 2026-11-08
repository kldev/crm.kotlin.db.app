package crm.offers

import crm.auth.CrmUserDetails
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.validation.Valid
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RestController

/** Contacts of users for the offers (ADR-0013): one's own for everybody, anyone's for administrators. */
@Tag(name = "Contacts")
@RestController
class ContactController(private val offers: OfferRepository) {

    @Operation(summary = "My contact as it closes my offers: job title, phone, e-mail.")
    @GetMapping("/api/auth/me/contact")
    fun getMyContact(@AuthenticationPrincipal actor: CrmUserDetails): UserContactResponse = offers.contact(actor.id, actor.id)

    @Operation(summary = "Set my contact (an empty value clears it).")
    @PutMapping("/api/auth/me/contact")
    fun updateMyContact(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @Valid @RequestBody body: UpdateContactRequest,
    ): UserContactResponse = offers.updateContact(actor.id, actor.id, body)

    @Operation(summary = "A user's contact (ADMIN, MANAGER).")
    @GetMapping("/api/users/{id}/contact")
    fun getUserContact(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Int): UserContactResponse =
        offers.contact(actor.id, id)

    @Operation(summary = "Set a user's contact (ADMIN).")
    @PutMapping("/api/users/{id}/contact")
    fun updateUserContact(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Int,
        @Valid @RequestBody body: UpdateContactRequest,
    ): UserContactResponse = offers.updateContact(actor.id, id, body)
}
