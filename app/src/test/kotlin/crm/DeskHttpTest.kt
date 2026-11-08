package crm

import crm.support.ApiClient
import crm.support.IntegrationTest
import crm.support.list
import org.junit.jupiter.api.Test
import tools.jackson.databind.JsonNode
import tools.jackson.databind.json.JsonMapper
import java.time.Duration
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Service desk (ADR-0007): a ticket is an event stream; the procedures decide every action. */
class DeskHttpTest : IntegrationTest() {

    private val json = JsonMapper.builder().build()

    private fun personId(email: String) = scalar<Int>("SELECT id FROM crm.people WHERE email = ?", email)!!

    private fun report(
        c: ApiClient,
        priority: String = "MEDIUM",
        reportedAt: Instant = Instant.now(),
        sub: String = "it.hardware",
        category: String = "it",
        title: String = "Test laptop ${System.nanoTime()}",
    ): JsonNode {
        val response = c.post(
            "/api/desk/tickets",
            mapOf(
                "title" to title, "description" to "Nie włącza się po aktualizacji.", "categoryKey" to category,
                "subcategoryKey" to sub, "priority" to priority, "reportedAt" to reportedAt.toString(),
                "requesterPersonId" to personId("adam.mazur@company.io"),
            ),
        )
        assertEquals(201, response.status, response.body.toString())
        return response.body!!
    }

    private fun id(ticket: JsonNode) = ticket["id"].asLong()

    private fun events(c: ApiClient, ticket: JsonNode) =
        c.get("/api/desk/tickets/${id(ticket)}/events").body!!.list()

    @Test
    fun `a reported ticket starts in the pool with its deadline from the SLA and one event`() {
        val c = loggedIn("anna.nowak")
        val reportedAt = Instant.now().minus(Duration.ofHours(2))
        val ticket = report(c, priority = "HIGH", reportedAt = reportedAt)
        assertEquals("IN_POOL", ticket["status"].asString())
        assertEquals("AGENT", ticket["channel"].asString())
        assertEquals("Anna Nowak", ticket["registeredByName"].asString())
        assertTrue(Regex("HAL-[0-9A-F]{8}").matches(ticket["number"].asString()))
        val deadline = Instant.parse(ticket["deadline"].asString())
        assertEquals(Duration.ofHours(8).toMinutes(), Duration.between(Instant.parse(ticket["reportedAt"].asString()), deadline).toMinutes())

        val stream = events(c, ticket)
        assertEquals(listOf("TicketReported"), stream.map { it["type"].asString() })
        val data = json.readTree(stream[0]["data"].asString())
        assertEquals("HIGH", data["priority"].asString())
        assertEquals("Adam Mazur", data["requester"]["name"].asString())
    }

    @Test
    fun `report rules - required fields, catalog, backdating and the requester`() {
        val c = loggedIn("anna.nowak")
        fun post(changes: Map<String, Any?>) = c.post(
            "/api/desk/tickets",
            mapOf(
                "title" to "Test", "description" to "Opis", "categoryKey" to "it", "subcategoryKey" to "it.hardware",
                "priority" to "LOW", "reportedAt" to Instant.now().toString(), "requesterIncognito" to true,
            ) + changes,
        )
        assertEquals(51105, post(mapOf("subcategoryKey" to "legal.contract"))["errorNumber"])
        assertEquals(51104, post(mapOf("categoryKey" to "nope"))["errorNumber"])
        assertEquals(51108, post(mapOf("reportedAt" to Instant.now().plus(Duration.ofMinutes(10)).toString()))["errorNumber"])
        assertEquals(51109, post(mapOf("reportedAt" to Instant.now().minus(Duration.ofDays(31)).toString()))["errorNumber"])
        assertEquals(
            51110,
            post(mapOf("requesterIncognito" to true, "requesterPersonId" to personId("adam.mazur@company.io")))["errorNumber"],
        )
        assertEquals(51110, post(mapOf("requesterIncognito" to false))["errorNumber"])
        assertEquals(400, post(mapOf("title" to " ")).status) // request validation, before the database
        assertEquals(201, post(emptyMap()).status)
    }

    private operator fun crm.support.ApiResponse.get(key: String): Int? = body?.get(key)?.takeUnless { it.isNull }?.asInt()

    @Test
    fun `take, hand over, return and resolve follow the rules of the assignee`() {
        val anna = loggedIn("anna.nowak")
        val piotr = loggedIn("piotr.kowalski")
        val ticket = report(anna)
        val t = "/api/desk/tickets/${id(ticket)}"
        val piotrId = piotr.get("/api/auth/me").body!!["id"].asInt()
        val annaId = anna.get("/api/auth/me").body!!["id"].asInt()

        assertEquals(51912, piotr.post("$t/resolve", null)["errorNumber"])
        val taken = anna.post("$t/take", null)
        assertEquals("IN_PROGRESS", taken.body!!["status"].asString())
        assertEquals(51910, piotr.post("$t/take", null)["errorNumber"])
        assertEquals(51312, piotr.post("$t/resolve", null)["errorNumber"])
        assertEquals(51114, anna.post("$t/hand-over", mapOf("toUserId" to annaId))["errorNumber"])

        val handed = anna.post("$t/hand-over", mapOf("toUserId" to piotrId, "reason" to "Urlop"))
        assertEquals(200, handed.status, handed.body.toString())
        assertEquals("Piotr Kowalski", handed.body!!["assigneeName"].asString())
        assertEquals(ticket["deadline"].asString(), handed.body!!["deadline"].asString(), "handover keeps the deadline")
        assertEquals(51311, anna.post("$t/return", mapOf<String, Any?>())["errorNumber"])

        val returned = piotr.post("$t/return", mapOf("reason" to "Nie mój zakres"))
        assertEquals("IN_POOL", returned.body!!["status"].asString())
        assertTrue(returned.body!!["assigneeUserId"].isNull)

        anna.post("$t/take", null)
        val resolved = anna.post("$t/resolve", null)
        assertEquals("DONE", resolved.body!!["status"].asString())
        assertEquals("Anna Nowak", resolved.body!!["assigneeName"].asString(), "a resolved ticket keeps who resolved it")
        assertEquals(false, resolved.body!!["resolvedLate"].asBoolean())
        assertEquals(51911, anna.post("$t/take", null)["errorNumber"])
        assertEquals(51911, anna.post("$t/priority", mapOf("priority" to "LOW"))["errorNumber"])

        assertEquals(
            listOf("TicketReported", "TicketTaken", "TicketHandedOver", "TicketReturnedToPool", "TicketTaken", "TicketResolved"),
            events(anna, ticket).map { it["type"].asString() },
        )
        assertEquals(6, resolved.body!!["version"].asInt())
    }

    @Test
    fun `two agents taking one ticket at once - exactly one wins`() {
        val clients = listOf(loggedIn("anna.nowak"), loggedIn("piotr.kowalski"), loggedIn("tomasz.wojcik"))
        val ticket = report(clients[0])
        val start = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(clients.size)
        val results = clients.map { c ->
            pool.submit<Int> {
                start.await()
                c.post("/api/desk/tickets/${id(ticket)}/take", null).status
            }
        }
        start.countDown()
        val statuses = results.map { it.get() }.sorted()
        pool.shutdown()
        assertEquals(listOf(200, 409, 409), statuses)
        assertEquals(2, events(clients[0], ticket).size)
    }

    @Test
    fun `resolving after the deadline is late for good`() {
        val c = loggedIn("anna.nowak")
        val ticket = report(c, priority = "CRITICAL", reportedAt = Instant.now().minus(Duration.ofHours(4)))
        c.post("/api/desk/tickets/${id(ticket)}/take", null)
        val resolved = c.post("/api/desk/tickets/${id(ticket)}/resolve", null).body!!
        assertEquals(true, resolved["resolvedLate"].asBoolean())
        val data = json.readTree(events(c, ticket).last()["data"].asString())
        assertEquals(true, data["late"].asBoolean())
    }

    @Test
    fun `priority change moves the deadline from the report date and the same priority is a no-op`() {
        val c = loggedIn("anna.nowak")
        val reportedAt = Instant.now().minus(Duration.ofHours(1))
        val ticket = report(c, priority = "LOW", reportedAt = reportedAt)
        val t = "/api/desk/tickets/${id(ticket)}"
        val changed = c.post("$t/priority", mapOf("priority" to "CRITICAL", "reason" to "Stoi produkcja")).body!!
        val from = Instant.parse(changed["reportedAt"].asString())
        assertEquals(180, Duration.between(from, Instant.parse(changed["deadline"].asString())).toMinutes())
        assertEquals("LOW", changed["originalPriority"].asString())
        val same = c.post("$t/priority", mapOf("priority" to "CRITICAL")).body!!
        assertEquals(changed["version"].asInt(), same["version"].asInt())
        assertEquals(2, events(c, ticket).size)
    }

    @Test
    fun `comments - any state, limits, stored as events and shown as text`() {
        val c = loggedIn("anna.nowak")
        val ticket = report(c)
        val t = "/api/desk/tickets/${id(ticket)}"
        assertEquals(400, c.post("$t/comments", mapOf("text" to "")).status)
        assertEquals(400, c.post("$t/comments", mapOf("text" to "x".repeat(2001))).status)
        val commented = c.post("$t/comments", mapOf("text" to "<script>alert(1)</script>")).body!!
        assertEquals(1, commented["commentCount"].asInt())
        val data = json.readTree(events(c, ticket).last()["data"].asString())
        assertEquals("<script>alert(1)</script>", data["text"].asString())
    }

    @Test
    fun `handler must come from the department of the category`() {
        val c = loggedIn("anna.nowak")
        val ticket = report(c, category = "hr-poland", sub = "hr-poland.pl.contract")
        val t = "/api/desk/tickets/${id(ticket)}"
        c.post("$t/take", null)
        val sales = personId("adam.mazur@company.io")
        val hr = personId("grzegorz.michalski@company.io")
        assertEquals(51115, c.post("$t/handler", mapOf("personId" to sales))["errorNumber"])
        val assigned = c.post("$t/handler", mapOf("personId" to hr, "reason" to "Ma dostęp do systemu")).body!!
        assertEquals("Grzegorz Michalski", assigned["handlerName"].asString())
        val cleared = c.post("$t/handler", mapOf("personId" to null)).body!!
        assertTrue(cleared["handlerPersonId"].isNull)
        assertEquals(3 + 1, events(c, ticket).size)
    }

    @Test
    fun `lists - pool and mine, open by deadline then resolved, keyset pages, count and counters`() {
        val c = loggedIn("magdalena.kaminska")
        val me = c.get("/api/auth/me").body!!["id"].asInt()
        val mine = report(c)
        c.post("/api/desk/tickets/${id(mine)}/take", null)

        val myList = c.get("/api/desk/tickets?scope=MINE&size=200").body!!["items"].list()
        assertTrue(myList.isNotEmpty() && myList.all { it["assigneeUserId"].asInt() == me && it["status"].asString() == "IN_PROGRESS" })
        val pool = c.get("/api/desk/tickets?scope=POOL&size=200").body!!["items"].list()
        assertTrue(pool.all { it["status"].asString() == "IN_POOL" })
        val deadlines = pool.map { Instant.parse(it["deadline"].asString()) }
        assertEquals(deadlines.sorted(), deadlines)

        // Every ticket exactly once over all pages, open ones first by deadline, then resolved newest first.
        val all = mutableListOf<JsonNode>()
        var cursor: String? = null
        do {
            val page = c.get("/api/desk/tickets?scope=ALL&size=7" + (cursor?.let { "&cursor=$it" } ?: "")).body!!
            all += page["items"].list()
            cursor = page["nextCursor"].takeUnless { it == null || it.isNull }?.asString()
        } while (cursor != null)
        assertEquals(scalar<Int>("SELECT COUNT(*) FROM crm.tickets"), all.size)
        assertEquals(all.size, all.map { it["id"].asLong() }.toSet().size)
        val firstDone = all.indexOfFirst { it["status"].asString() == "DONE" }
        assertTrue(firstDone > 0 && all.drop(firstDone).all { it["status"].asString() == "DONE" })
        val resolved = all.drop(firstDone).map { Instant.parse(it["resolvedAt"].asString()) }
        assertEquals(resolved.sortedDescending(), resolved)

        assertEquals(all.size.toLong(), c.get("/api/desk/tickets/count").body!!["total"].asLong())
        val counters = c.get("/api/desk/tickets/counters").body!!
        assertEquals(myList.size, counters["mine"].asInt())
        assertEquals(pool.size, counters["pool"].asInt())
        val overdue = c.get("/api/desk/tickets?deadline=OVERDUE&size=200").body!!["items"].list()
        assertEquals(overdue.size, counters["overdue"].asInt())
        assertTrue(overdue.all { Instant.parse(it["deadline"].asString()) <= Instant.now() && it["status"].asString() != "DONE" })

        val byNumber = c.get("/api/desk/tickets?search=${mine["number"].asString().lowercase()}").body!!["items"].list()
        assertEquals(listOf(id(mine)), byNumber.map { it["id"].asLong() })
        assertEquals(id(mine), c.get("/api/desk/tickets/by-number/${mine["number"].asString()}").body!!["id"].asLong())
        assertEquals(400, c.get("/api/desk/tickets?scope=NOPE").status)
    }

    @Test
    fun `public form - catalog and names without sign-in, a ticket into the pool, nothing else`() {
        val anonymous = client()
        val catalog = anonymous.get("/api/public/desk/catalog").body!!
        assertEquals(8, catalog["categories"].list().size)
        assertEquals(4, catalog["priorities"].list().size)
        val people = anonymous.get("/api/public/desk/people").body!!.list()
        assertTrue(people.size >= 40)
        assertNull(people[0].get("email"), "the public list has no contacts")
        assertEquals(401, anonymous.get("/api/desk/tickets").status)

        anonymous.csrf()
        val sent = anonymous.post(
            "/api/public/desk/tickets",
            mapOf(
                "title" to "Test z formularza", "description" to "Drukarka", "categoryKey" to "it",
                "subcategoryKey" to "it.hardware", "priority" to "LOW", "requesterIncognito" to true,
            ),
        )
        assertEquals(201, sent.status, sent.body.toString())
        val number = sent.body!!["number"].asString()
        assertNotNull(sent.body!!["deadline"])
        val ticket = loggedIn("anna.nowak").get("/api/desk/tickets/by-number/$number").body!!
        assertEquals("SELF_SERVICE", ticket["channel"].asString())
        assertEquals("IN_POOL", ticket["status"].asString())
        assertTrue(ticket["requesterIncognito"].asBoolean())
    }

    @Test
    fun `agents and people lists`() {
        val c = loggedIn("anna.nowak")
        val agents = c.get("/api/desk/agents?search=Anna").body!!["items"].list()
        assertTrue(agents.any { it["login"].asString() == "anna.nowak" })
        assertTrue(agents.all { it["displayName"].asString().startsWith("Anna") || it["login"].asString().startsWith("anna") })
        val people = c.get("/api/desk/people").body!!.list()
        assertTrue(people.any { it["email"].asString() == "adam.mazur@company.io" })
    }
}
