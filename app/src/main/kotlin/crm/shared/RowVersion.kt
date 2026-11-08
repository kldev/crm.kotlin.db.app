package crm.shared

import java.util.HexFormat

/** SQL Server `rowversion` (binary(8)) as a 16-character hex string in the API. */
object RowVersion {
    private val hex = HexFormat.of()

    fun format(bytes: ByteArray): String = hex.formatHex(bytes)

    fun parse(value: String): ByteArray = hex.parseHex(value)

    const val PATTERN = "^[0-9a-fA-F]{16}$"
}
