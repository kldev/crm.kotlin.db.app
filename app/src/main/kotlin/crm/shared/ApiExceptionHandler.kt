package crm.shared

import crm.auth.InvalidLoginException
import crm.auth.WrongCurrentPasswordException
import org.slf4j.LoggerFactory
import org.springframework.dao.DataAccessException
import org.springframework.http.HttpStatus
import org.springframework.http.ProblemDetail
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler

/**
 * Errors as RFC 9457 ProblemDetail. Request validation (jakarta.validation) is handled by the base class;
 * database rules come as THROW numbers and are translated by [ProcedureErrors].
 */
@RestControllerAdvice
class ApiExceptionHandler : ResponseEntityExceptionHandler() {
    private val log = LoggerFactory.getLogger(javaClass)

    @ExceptionHandler(DataAccessException::class)
    fun handleDatabase(error: DataAccessException): ProblemDetail {
        val sql = ProcedureErrors.findSqlException(error)
        val number = sql?.errorCode ?: 0
        val mapping = ProcedureErrors.map(number)
        if (mapping.status.is5xxServerError) {
            log.error("Database call failed (SQL error {})", number, error)
        }
        val detail = if (mapping.exposeMessage) sql?.message else null
        return ProblemDetail.forStatusAndDetail(mapping.status, detail ?: mapping.title).apply {
            title = mapping.title
            setProperty("errorNumber", number.takeIf { mapping.exposeMessage || it in setOf(2601, 2627, 547, 1205) })
        }
    }

    @ExceptionHandler(InvalidLoginException::class)
    fun handleInvalidLogin(error: InvalidLoginException): ProblemDetail =
        ProblemDetail.forStatusAndDetail(HttpStatus.UNAUTHORIZED, error.message!!).apply { title = "Unauthorized" }

    @ExceptionHandler(WrongCurrentPasswordException::class)
    fun handleWrongPassword(error: WrongCurrentPasswordException): ProblemDetail =
        ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, error.message!!).apply { title = "Validation failed" }

    @ExceptionHandler(crm.desk.TooManyPublicReportsException::class)
    fun handleTooManyReports(error: crm.desk.TooManyPublicReportsException): ProblemDetail =
        ProblemDetail.forStatusAndDetail(HttpStatus.TOO_MANY_REQUESTS, error.message!!).apply { title = "Too many requests" }

    /** The attachments bucket did not answer (ADR-0009). */
    @ExceptionHandler(software.amazon.awssdk.core.exception.SdkException::class)
    fun handleStorage(error: software.amazon.awssdk.core.exception.SdkException): ProblemDetail {
        log.error("Attachment storage call failed", error)
        return ProblemDetail.forStatusAndDetail(HttpStatus.SERVICE_UNAVAILABLE, "File storage is not available.").apply {
            title = "Storage unavailable"
        }
    }

    @ExceptionHandler(crm.desk.reports.UnknownReportException::class)
    fun handleUnknownReport(error: crm.desk.reports.UnknownReportException): ProblemDetail =
        ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, error.message!!).apply { title = "Not found" }

    @ExceptionHandler(InvalidCursorException::class)
    fun handleCursor(error: InvalidCursorException): ProblemDetail =
        ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, error.message ?: "Invalid cursor.").apply {
            title = "Validation failed"
        }
}
