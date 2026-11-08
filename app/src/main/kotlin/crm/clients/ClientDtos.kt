package crm.clients

import crm.shared.RowVersion
import jakarta.validation.constraints.Email
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import java.time.LocalDateTime

/** Row of the clients list (without the note). */
data class ClientSummary(
    val id: Long,
    val name: String,
    val nip: String?,
    val email: String?,
    val phone: String?,
    val city: String?,
    val status: String,
    val assignedUserId: Int?,
    val assignedUserLogin: String?,
    val createdAt: LocalDateTime,
    val updatedAt: LocalDateTime,
    val rowVersion: String,
)

data class ClientResponse(
    val id: Long,
    val name: String,
    val nip: String?,
    val email: String?,
    val phone: String?,
    val city: String?,
    val status: String,
    val assignedUserId: Int?,
    val assignedUserLogin: String?,
    val note: String?,
    val createdAt: LocalDateTime,
    val createdBy: Int?,
    val updatedAt: LocalDateTime,
    val updatedBy: Int?,
    val rowVersion: String,
)

/** Create and full update share the fields; the update also carries `rowVersion` read from the server. */
data class ClientRequest(
    @field:NotBlank @field:Size(max = 200) val name: String?,
    @field:Size(max = 20) val nip: String?,
    @field:Email @field:Size(max = 254) val email: String?,
    @field:Size(max = 30) val phone: String?,
    @field:Size(max = 100) val city: String?,
    @field:NotBlank @field:Pattern(regexp = "LEAD|ACTIVE|INACTIVE") val status: String?,
    val assignedUserId: Int?,
    @field:Size(max = 2000) val note: String?,
    @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String? = null,
)
