package crm.shared

import org.springframework.http.HttpStatus
import java.sql.SQLException

/**
 * Catalogue of errors raised by the T-SQL procedures (THROW number -> HTTP status), ADR-0002.
 * The procedures decide the rule; this table only translates the number for HTTP.
 */
object ProcedureErrors {
    /** Status for a SQL Server error number, and whether its message may be shown to the API client. */
    data class Mapping(val status: HttpStatus, val exposeMessage: Boolean, val title: String)

    fun map(errorNumber: Int): Mapping = when (errorNumber) {
        in 51000..51299 -> Mapping(HttpStatus.BAD_REQUEST, true, "Validation failed")
        in 51300..51399 -> Mapping(HttpStatus.FORBIDDEN, true, "Forbidden")
        in 51400..51499 -> Mapping(HttpStatus.NOT_FOUND, true, "Not found")
        in 51900..51999 -> Mapping(HttpStatus.CONFLICT, true, "Conflict")
        2601, 2627 -> Mapping(HttpStatus.CONFLICT, false, "Already exists")
        547 -> Mapping(HttpStatus.BAD_REQUEST, false, "Invalid reference")
        1205 -> Mapping(HttpStatus.SERVICE_UNAVAILABLE, false, "Please retry")
        else -> Mapping(HttpStatus.INTERNAL_SERVER_ERROR, false, "Database error")
    }

    /** The first SQLException in the cause chain (Spring wraps it in a DataAccessException). */
    fun findSqlException(error: Throwable): SQLException? {
        var current: Throwable? = error
        while (current != null) {
            if (current is SQLException) return current
            current = current.cause
        }
        return null
    }
}
