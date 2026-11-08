package crm.clients

import crm.auth.CrmUserDetails
import crm.shared.Cursor
import crm.shared.InvalidCursorException
import crm.shared.PageResponse
import crm.shared.RowVersion
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.validation.Valid
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import jakarta.validation.constraints.Pattern
import org.springframework.http.HttpStatus
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.validation.annotation.Validated
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
import org.springframework.web.server.ResponseStatusException

@Tag(name = "Clients")
@Validated
@RestController
@RequestMapping("/api/clients")
class ClientController(private val clients: ClientRepository) {

    @Operation(
        summary = "Clients page. With `namePrefix` ordered by name, otherwise newest first. " +
            "SALES users see only clients assigned to them.",
    )
    @GetMapping
    fun search(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(required = false) namePrefix: String?,
        @RequestParam(required = false) nip: String?,
        @RequestParam(required = false) email: String?,
        @RequestParam(required = false) city: String?,
        @RequestParam(required = false) status: String?,
        @RequestParam(required = false) cursor: String?,
        @RequestParam(defaultValue = "50") @Min(1) @Max(200) size: Int,
    ): PageResponse<ClientSummary> {
        val filter = ClientFilter(namePrefix?.takeIf { it.isNotBlank() }, nip, email, city, status)
        // Cursor = (id) when ordered by id, (id, name) when ordered by name.
        val byName = filter.namePrefix != null
        val parts = Cursor.decode(cursor, if (byName) 2 else 1)
        val afterId = parts?.let { it[0].toLongOrNull() ?: throw InvalidCursorException("Invalid cursor.") }
        val afterName = if (byName) parts?.get(1) else null

        val rows = clients.search(actor.id, filter, afterId, afterName, size)
        return Cursor.page(rows, size) { if (byName) Cursor.encode(it.id, it.name) else Cursor.encode(it.id) }
    }

    @Operation(summary = "Client details.")
    @GetMapping("/{id}")
    fun get(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Long): ClientResponse =
        clients.get(actor.id, id)

    @Operation(summary = "Create a client. A SALES user creates clients assigned to themselves.")
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    fun create(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @Valid @RequestBody body: ClientRequest,
    ): ClientResponse = clients.create(actor.id, body)

    @Operation(summary = "Update a client. `rowVersion` from the last read is required (409 when it changed).")
    @PutMapping("/{id}")
    fun update(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: ClientRequest,
    ): ClientResponse {
        val rowVersion = body.rowVersion
            ?: throw ResponseStatusException(HttpStatus.BAD_REQUEST, "rowVersion is required.")
        return clients.update(actor.id, id, body, rowVersion)
    }

    @Operation(summary = "Delete a client without projects (MANAGER, ADMIN).")
    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun delete(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @RequestParam @Pattern(regexp = RowVersion.PATTERN) rowVersion: String,
    ) {
        clients.delete(actor.id, id, rowVersion)
    }
}
