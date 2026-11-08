package crm

import crm.support.ApiClient
import crm.support.IntegrationTest
import crm.support.Part
import crm.support.RustFs
import crm.support.list
import org.junit.jupiter.api.Test
import tools.jackson.databind.json.JsonMapper
import java.time.Instant
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Desk attachments (ADR-0009): the procedure decides, the bytes go to S3, a refusal leaves no object behind. */
class DeskAttachmentHttpTest : IntegrationTest() {

    private val json = JsonMapper.builder().build()

    private val png = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4)

    private fun newTicket(c: ApiClient): Long {
        val response = c.post(
            "/api/desk/tickets",
            mapOf(
                "title" to "Test załączniki ${System.nanoTime()}", "description" to "Zrzut ekranu w załączniku",
                "categoryKey" to "it", "subcategoryKey" to "it.application", "priority" to "LOW",
                "reportedAt" to Instant.now().toString(), "requesterIncognito" to true,
            ),
        )
        assertEquals(201, response.status, response.body.toString())
        return response.body!!["id"].asLong()
    }

    private fun file(name: String, content: ByteArray = png, type: String = "application/octet-stream") =
        Part("files", content, name, type)

    @Test
    fun `an agent attaches files - events, read model, inline image and downloaded document`() {
        val c = loggedIn("anna.nowak")
        val id = newTicket(c)
        val before = RustFs.keys()
        val text = "linia 1\nlinia 2".toByteArray()
        // The browser's claimed type is ignored: the extension decides.
        val response = c.multipart(
            "/api/desk/tickets/$id/attachments",
            listOf(file("C:\\Users\\anna\\zrzut ekranu.png", type = "text/html"), file("log.txt", text)),
        )
        assertEquals(200, response.status, response.body.toString())
        assertEquals(2, response.body!!["attachmentCount"].asInt())
        assertEquals(2, (RustFs.keys() - before).size)

        val list = c.get("/api/desk/tickets/$id/attachments").body!!.list()
        assertEquals(listOf("zrzut ekranu.png", "log.txt").sorted(), list.map { it["fileName"].asString() }.sorted())
        val image = list.first { it["fileName"].asString().endsWith(".png") }
        assertEquals("image/png", image["contentType"].asString())
        assertTrue(image["inline"].asBoolean())

        val shown = c.download("/api/desk/tickets/$id/attachments/${image["id"].asString()}")
        assertEquals(200, shown.status)
        assertContentEquals(png, shown.bytes)
        assertEquals("image/png", shown.header("Content-Type"))
        assertTrue(shown.header("Content-Disposition")!!.startsWith("inline"))
        assertEquals("nosniff", shown.header("X-Content-Type-Options"))
        assertEquals("sandbox", shown.header("Content-Security-Policy"))

        val document = list.first { it["fileName"].asString() == "log.txt" }
        val downloaded = c.download("/api/desk/tickets/$id/attachments/${document["id"].asString()}")
        assertTrue(downloaded.header("Content-Disposition")!!.startsWith("attachment"))
        assertContentEquals(text, downloaded.bytes)

        val events = c.get("/api/desk/tickets/$id/events").body!!.list().filter { it["type"].asString() == "TicketAttachmentAdded" }
        assertEquals(2, events.size)
        val data = json.readTree(events[0]["data"].asString())
        assertEquals("Anna Nowak", data["addedBy"].asString())
        assertEquals("Anna Nowak", data["agent"]["name"].asString())
    }

    @Test
    fun `refused files - SVG, HTML, empty, no extension - and nothing is stored`() {
        val c = loggedIn("anna.nowak")
        val id = newTicket(c)
        val before = RustFs.keys()
        fun refused(part: Part) = c.multipart("/api/desk/tickets/$id/attachments", listOf(part))
        assertEquals(51121, refused(file("logo.svg", "<svg/>".toByteArray()))["errorNumber"])
        assertEquals(51121, refused(file("strona.html", "<html/>".toByteArray()))["errorNumber"])
        assertEquals(51121, refused(file("README"))["errorNumber"])
        assertEquals(51122, refused(file("pusty.pdf", ByteArray(0)))["errorNumber"])
        // One bad file refuses the whole request before any byte is stored.
        assertEquals(51121, c.multipart("/api/desk/tickets/$id/attachments", listOf(file("ok.png"), file("zly.exe")))["errorNumber"])
        assertEquals(before, RustFs.keys())
        assertEquals(0, c.get("/api/desk/tickets/$id").body!!["attachmentCount"].asInt())
    }

    @Test
    fun `at most 10 per ticket - the refused upload is deleted from the bucket`() {
        val c = loggedIn("anna.nowak")
        val id = newTicket(c)
        assertEquals(200, c.multipart("/api/desk/tickets/$id/attachments", (1..8).map { file("zrzut$it.png") }).status)
        val before = RustFs.keys()
        val tooMany = c.multipart("/api/desk/tickets/$id/attachments", (1..3).map { file("wiecej$it.png") })
        assertEquals(400, tooMany.status)
        assertEquals(51124, tooMany["errorNumber"])
        assertEquals(before, RustFs.keys(), "files stored before the refusal are deleted again")
        assertEquals(200, c.multipart("/api/desk/tickets/$id/attachments", (1..2).map { file("ostatnie$it.png") }).status)
    }

    @Test
    fun `the public form sends the ticket and its files in one request`() {
        val anonymous = client()
        anonymous.csrf()
        val fields = mapOf(
            "title" to "Test formularz z plikiem", "description" to "Drukarka drukuje puste strony",
            "categoryKey" to "it", "subcategoryKey" to "it.hardware", "priority" to "MEDIUM",
            "requesterIncognito" to "true",
        ).map { (k, v) -> Part(k, v.toByteArray()) }
        val sent = anonymous.multipart("/api/public/desk/tickets", fields + file("strona.pdf", "%PDF-1.4".toByteArray()))
        assertEquals(201, sent.status, sent.body.toString())

        val agent = loggedIn("anna.nowak")
        val ticket = agent.get("/api/desk/tickets/by-number/${sent.body!!["number"].asString()}").body!!
        assertEquals(1, ticket["attachmentCount"].asInt())
        val attachment = agent.get("/api/desk/tickets/${ticket["id"].asLong()}/attachments").body!!.list().single()
        assertEquals("incognito", attachment["addedBy"].asString())
        assertEquals(401, anonymous.download("/api/desk/tickets/${ticket["id"].asLong()}/attachments/${attachment["id"].asString()}").status)

        val noFile = anonymous.multipart("/api/public/desk/tickets", fields)
        assertEquals(201, noFile.status, noFile.body.toString())
        val badFile = anonymous.multipart("/api/public/desk/tickets", fields + file("skrypt.svg", "<svg/>".toByteArray()))
        assertEquals(51121, badFile["errorNumber"])
    }

    @Test
    fun `an unknown attachment is 404`() {
        val c = loggedIn("anna.nowak")
        val id = newTicket(c)
        assertEquals(404, c.download("/api/desk/tickets/$id/attachments/00000000-0000-0000-0000-000000000001").status)
    }

    private operator fun crm.support.ApiResponse.get(key: String): Int? = body?.get(key)?.takeUnless { it.isNull }?.asInt()
}
