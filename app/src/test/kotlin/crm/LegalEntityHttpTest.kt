package crm

import crm.support.ApiClient
import crm.support.IntegrationTest
import crm.support.list
import org.junit.jupiter.api.Test
import org.openpdf.text.pdf.PdfReader
import org.openpdf.text.pdf.parser.PdfTextExtractor
import tools.jackson.databind.JsonNode
import java.time.LocalDate
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** The group's companies: projects delivered and offers signed by one of them (ADR-0016). */
class LegalEntityHttpTest : IntegrationTest() {

    private operator fun crm.support.ApiResponse.get(key: String): Int? = body?.get(key)?.takeUnless { it.isNull }?.asInt()

    private fun entity(c: ApiClient, name: String) = c.get("/api/legal-entities").body!!.list().first { it["name"].asString() == name }

    /** A valid NIP for a number: the 9 digits and the check digit (none when it would be 10). */
    private fun nip(seed: Long): String {
        val w = intArrayOf(6, 5, 7, 2, 3, 4, 5, 6, 7)
        var n = seed
        while (true) {
            val digits = (n % 1_000_000_000).toString().padStart(9, '0')
            val check = digits.mapIndexed { i, d -> (d - '0') * w[i] }.sum() % 11
            if (check < 10) return digits + check
            n++
        }
    }

    private fun body(name: String, taxId: String, from: LocalDate, to: LocalDate? = null, rowVersion: String? = null) = mapOf(
        "name" to name, "legalName" to "$name sp. z o.o.", "taxId" to taxId, "address" to "ul. Testowa 1, Kraków",
        "phone" to "+48 12 000 00 00", "email" to "Biuro@Test.example", "activeFrom" to from.toString(),
        "activeTo" to to?.toString(), "rowVersion" to rowVersion,
    )

    @Test
    fun `four companies, everybody reads them, the template names its company`() {
        val sales = loggedIn("perf.sales.0001")
        val all = sales.get("/api/legal-entities").body!!.list()
        assertTrue(all.map { it["name"].asString() }.containsAll(listOf("Halycon Inc.", "Halycon Budownictwo", "Halycon IT", "Halycon Staff")))
        assertTrue(all.all { it["trading"].asBoolean() || !it["activeTo"].isNull })
        val templates = sales.get("/api/offers/templates").body!!.list().associate { it["key"].asString() to it["legalEntityId"].asInt() }
        assertEquals(entity(sales, "Halycon IT")["id"].asInt(), templates["IT"])
    }

    @Test
    fun `an administrator adds, checks and closes a company`() {
        val admin = loggedIn(ADMIN_LOGIN, ADMIN_PASSWORD)
        val name = "Test Spółka ${System.nanoTime()}"
        val taxId = nip(System.nanoTime() / 1000)
        assertEquals(403, loggedIn("perf.manager.0001").post("/api/legal-entities", body(name, taxId, LocalDate.now())).status)
        assertEquals(51202, admin.post("/api/legal-entities", body(name, "1234567890", LocalDate.now()))["errorNumber"])
        assertEquals(51203, admin.post("/api/legal-entities", body(name, taxId, LocalDate.now(), LocalDate.now().minusDays(1)))["errorNumber"])
        val created = admin.post("/api/legal-entities", body(name, taxId.substring(0, 3) + "-" + taxId.substring(3), LocalDate.now())).body!!
        assertEquals(taxId, created["taxId"].asString())
        assertEquals("biuro@test.example", created["email"].asString())
        assertEquals(409, admin.post("/api/legal-entities", body("$name 2", taxId, LocalDate.now())).status, "duplicate NIP")
        val closed = admin.put(
            "/api/legal-entities/${created["id"].asInt()}",
            body(name, taxId, LocalDate.now().minusDays(10), LocalDate.now().minusDays(1), created["rowVersion"].asString()),
        ).body!!
        assertFalse(closed["trading"].asBoolean())
        assertEquals(409, admin.put("/api/legal-entities/${created["id"].asInt()}", body(name, taxId, LocalDate.now(), null, created["rowVersion"].asString())).status)
    }

    @Test
    fun `a project is delivered by a trading company, changed only while new`() {
        val c = loggedIn("perf.sales.0001")
        val me = c.get("/api/auth/me").body!!["id"].asInt()
        val team = scalar<Int>("SELECT TOP 1 team_id FROM crm.team_members WHERE user_id = $me")!!
        val client = c.post("/api/clients", mapOf("name" to "Test Spółkowy ${System.nanoTime()}", "status" to "ACTIVE")).body!!["id"].asLong()
        val staff = entity(c, "Halycon Staff")["id"].asInt()
        fun project(entityId: Int, start: LocalDate) = c.post(
            "/api/projects",
            mapOf("clientId" to client, "teamId" to team, "ownerUserId" to me, "name" to "Test", "startDate" to start.toString(),
                "dueDate" to start.plusDays(30).toString(), "budget" to 100, "legalEntityId" to entityId),
        )
        assertEquals(51205, project(staff, LocalDate.of(2021, 1, 1))["errorNumber"], "Staff trades from 2022-06")
        assertEquals(51408, project(9999, LocalDate.now())["errorNumber"])
        val p = project(staff, LocalDate.now()).body!!
        assertEquals("Halycon Staff", p["legalEntityName"].asString())
        val it = entity(c, "Halycon IT")["id"].asInt()
        fun update(project: JsonNode, entityId: Int) = c.put(
            "/api/projects/${project["id"].asLong()}",
            mapOf("teamId" to team, "ownerUserId" to me, "name" to "Test", "startDate" to project["startDate"].asString(),
                "dueDate" to project["dueDate"].asString(), "budget" to 100, "legalEntityId" to entityId,
                "rowVersion" to project["rowVersion"].asString()),
        )
        val moved = update(p, it).body!!
        assertEquals("Halycon IT", moved["legalEntityName"].asString())
        val accepted = c.post("/api/projects/${p["id"].asLong()}/stage", mapOf("stage" to "ACCEPTED", "rowVersion" to moved["rowVersion"].asString())).body!!
        assertEquals(51908, update(accepted, staff)["errorNumber"])
        val listed = c.get("/api/projects?clientId=$client&legalEntityId=$it").body!!["items"].list()
        assertEquals(listOf(p["id"].asLong()), listed.map { it["id"].asLong() })
        assertTrue(c.get("/api/projects?clientId=$client&legalEntityId=$staff").body!!["items"].list().isEmpty())
    }

    @Test
    fun `an offer is signed by its template's company, or another one, and the PDF says so`() {
        val c = loggedIn("perf.sales.0001")
        val client = c.post("/api/clients", mapOf("name" to "Test Ofertowy ${System.nanoTime()}", "status" to "ACTIVE")).body!!["id"].asLong()
        val offer = c.post("/api/offers", mapOf("clientId" to client, "templateKey" to "CONSTRUCTION")).body!!
        assertEquals("Halycon Budownictwo", offer["legalEntityName"].asString())
        val inc = entity(c, "Halycon Inc.")["id"].asInt()
        val other = c.post("/api/offers", mapOf("clientId" to client, "templateKey" to "IT", "legalEntityId" to inc)).body!!
        assertEquals("Halycon Inc.", other["legalEntityName"].asString())
        assertEquals(listOf(other["id"].asLong()), c.get("/api/offers?clientId=$client&legalEntityId=$inc").body!!["items"].list().map { it["id"].asLong() })
        val pdf = c.download("/api/offers/${offer["id"].asLong()}/pdf")
        val reader = PdfReader(pdf.bytes)
        val text = (1..reader.numberOfPages).joinToString("\n") { PdfTextExtractor(reader).getTextFromPage(it) }
        assertTrue("Halycon Budownictwo" in text && "526-000-00-28" in text, text.take(400))
    }
}
