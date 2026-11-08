package crm.shared

import java.sql.ResultSet
import java.time.LocalDate
import java.time.LocalDateTime

// Small readers for nullable columns; the JDBC API returns 0/false for SQL NULL otherwise.

fun ResultSet.getIntOrNull(column: String): Int? = getInt(column).takeUnless { wasNull() }

fun ResultSet.getLongOrNull(column: String): Long? = getLong(column).takeUnless { wasNull() }

fun ResultSet.getLocalDateTime(column: String): LocalDateTime = getObject(column, LocalDateTime::class.java)

fun ResultSet.getLocalDateTimeOrNull(column: String): LocalDateTime? = getObject(column, LocalDateTime::class.java)

fun ResultSet.getLocalDate(column: String): LocalDate = getObject(column, LocalDate::class.java)

fun ResultSet.getRowVersion(column: String = "row_version"): String = RowVersion.format(getBytes(column))

/** A datetime2 column stored in UTC (the desk stores every instant so) as an Instant. */
fun ResultSet.getInstant(column: String): java.time.Instant =
    getObject(column, LocalDateTime::class.java).toInstant(java.time.ZoneOffset.UTC)

fun ResultSet.getInstantOrNull(column: String): java.time.Instant? =
    getObject(column, LocalDateTime::class.java)?.toInstant(java.time.ZoneOffset.UTC)

/** An instant as the UTC LocalDateTime a datetime2 parameter expects. */
fun java.time.Instant.toUtcLocalDateTime(): LocalDateTime = LocalDateTime.ofInstant(this, java.time.ZoneOffset.UTC)
