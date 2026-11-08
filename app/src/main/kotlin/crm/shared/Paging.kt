package crm.shared

import java.util.Base64

/** One page of a keyset-paged list. `nextCursor` is null on the last page; pass it back as `cursor`. */
data class PageResponse<T>(val items: List<T>, val nextCursor: String?)

class InvalidCursorException(message: String) : RuntimeException(message)

/**
 * Opaque keyset cursors: the values of the last row of a page, base64url-encoded, so clients do not depend on the
 * sort key. Each list decodes its own shape.
 */
object Cursor {
    private const val SEPARATOR = '\u001F'

    fun encode(vararg parts: Any?): String =
        Base64.getUrlEncoder().withoutPadding()
            .encodeToString(parts.joinToString(SEPARATOR.toString()) { it?.toString() ?: "" }.toByteArray())

    fun decode(cursor: String?, expectedParts: Int): List<String>? {
        if (cursor.isNullOrBlank()) return null
        val parts = try {
            String(Base64.getUrlDecoder().decode(cursor)).split(SEPARATOR)
        } catch (_: IllegalArgumentException) {
            throw InvalidCursorException("Invalid cursor.")
        }
        if (parts.size != expectedParts) throw InvalidCursorException("Invalid cursor.")
        return parts
    }

    /** Cuts the extra row the procedures return (page_size + 1) and builds the next cursor from the last item. */
    fun <T> page(rows: List<T>, pageSize: Int, cursorOf: (T) -> String): PageResponse<T> {
        val hasMore = rows.size > pageSize
        val items = if (hasMore) rows.take(pageSize) else rows
        return PageResponse(items, if (hasMore) cursorOf(items.last()) else null)
    }
}
