package crm

import org.junit.jupiter.api.Test
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.extension
import kotlin.io.path.readText
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** ADR-0002: the Kotlin code calls procedures and nothing else. */
class ArchitectureTest {
    private val sources: List<Path> = Files.walk(Path.of("src/main/kotlin")).use { paths ->
        paths.filter { it.extension == "kt" }.toList()
    }

    private val stringLiteral = Regex("\"(?:[^\"\\\\]|\\\\.)*\"")

    @Test
    fun `no SQL statement text in the application code`() {
        val sqlWord = Regex("\\b(SELECT|INSERT|UPDATE|DELETE|MERGE|TRUNCATE|CREATE|ALTER|DROP)\\b")
        val offenders = sources.flatMap { file ->
            stringLiteral.findAll(file.readText())
                .map { it.value }
                .filter { sqlWord.containsMatchIn(it) }
                .map { "$file: $it" }
        }
        assertEquals(emptyList(), offenders)
    }

    @Test
    fun `every database call is EXEC of a procedure in schema app or seed`() {
        val execs = sources.flatMap { file ->
            stringLiteral.findAll(file.readText()).map { it.value.trim('"') }.filter { it.startsWith("EXEC ") }.toList()
        }
        assertTrue(execs.size >= 30, "expected the procedure calls to be found, got ${execs.size}")
        val wrong = execs.filterNot { Regex("^EXEC (app|seed)\\.[a-z_]+( |$)").containsMatchIn(it) }
        assertEquals(emptyList(), wrong)
    }

    @Test
    fun `no ORM or query mapper in the imports`() {
        val forbidden = listOf("jakarta.persistence", "org.hibernate", "org.springframework.data", "org.jooq", "org.jetbrains.exposed")
        val offenders = sources.filter { file -> forbidden.any { file.readText().contains("import $it") } }
        assertEquals(emptyList(), offenders)
    }
}
