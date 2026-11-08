package crm

import crm.support.ApiClient
import crm.support.IntegrationTest
import crm.support.list
import org.junit.jupiter.api.Test
import tools.jackson.databind.JsonNode
import java.math.BigDecimal
import java.time.LocalDate
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The sales pipeline as a kanban board (ADR-0015). */
class DealHttpTest : IntegrationTest() {

    private operator fun crm.support.ApiResponse.get(key: String): Int? = body?.get(key)?.takeUnless { it.isNull }?.asInt()

    private fun me(c: ApiClient) = c.get("/api/auth/me").body!!["id"].asInt()

    private fun ownClient(c: ApiClient): Long =
        c.post("/api/clients", mapOf("name" to "Test Lejek ${System.nanoTime()}", "city" to "Gdańsk", "status" to "ACTIVE"))
            .body!!["id"].asLong()

    private fun deal(c: ApiClient, clientId: Long, value: Any = 12000.50): JsonNode {
        val response = c.post(
            "/api/deals",
            mapOf("clientId" to clientId, "title" to "Wdrożenie testowe", "value" to value, "expectedClose" to LocalDate.now().plusDays(30).toString()),
        )
        assertEquals(201, response.status, response.body.toString())
        return response.body!!
    }

    @Test
    fun `stages in order with probabilities`() {
        val stages = loggedIn("perf.sales.0001").get("/api/deals/stages").body!!.list()
        assertEquals(listOf("LEAD", "QUALIFIED", "PROPOSAL", "NEGOTIATION", "WON", "LOST"), stages.map { it["stage"].asString() })
        assertEquals(listOf(10, 25, 50, 75, 100, 0), stages.map { it["probability"].asInt() })
    }

    @Test
    fun `a deal starts as a lead, moves across the board, lost needs a reason`() {
        val sales = loggedIn("perf.sales.0001")
        val d = deal(sales, ownClient(sales))
        assertEquals("LEAD", d["stage"].asString())
        assertEquals(me(sales), d["ownerUserId"].asInt())
        val id = d["id"].asLong()

        val proposal = sales.post("/api/deals/$id/move", mapOf("stage" to "PROPOSAL", "rowVersion" to d["rowVersion"].asString())).body!!
        assertEquals(50, proposal["probability"].asInt())
        assertEquals(51197, sales.post("/api/deals/$id/move", mapOf("stage" to "LOST", "rowVersion" to proposal["rowVersion"].asString()))["errorNumber"])
        assertEquals(51196, sales.post("/api/deals/$id/move", mapOf("stage" to "NOPE", "rowVersion" to proposal["rowVersion"].asString()))["errorNumber"])
        val lost = sales.post(
            "/api/deals/$id/move",
            mapOf("stage" to "LOST", "lostReason" to "Za drogo", "rowVersion" to proposal["rowVersion"].asString()),
        ).body!!
        assertTrue(lost["closed"].asBoolean() && !lost["closedAt"].isNull)
        assertEquals(409, sales.post("/api/deals/$id/move", mapOf("stage" to "WON", "rowVersion" to proposal["rowVersion"].asString())).status)
        val back = sales.post("/api/deals/$id/move", mapOf("stage" to "NEGOTIATION", "rowVersion" to lost["rowVersion"].asString())).body!!
        assertTrue(back["closedAt"].isNull && back["lostReason"].isNull)

        val updated = sales.put(
            "/api/deals/$id",
            mapOf("title" to "Wdrożenie CRM", "value" to 99000, "currency" to "EUR", "expectedClose" to LocalDate.now().toString(),
                "rowVersion" to back["rowVersion"].asString()),
        ).body!!
        assertEquals(0, BigDecimal("99000").compareTo(BigDecimal(updated["value"].asString())))
        assertEquals("EUR", updated["currency"].asString())
        assertTrue(sales.get("/api/deals?scope=MINE").body!!.list().any { it["id"].asLong() == id })
        assertEquals(204, sales.delete("/api/deals/$id?rowVersion=${updated["rowVersion"].asString()}").status)
        assertEquals(404, sales.get("/api/deals/$id").status)
    }

    @Test
    fun `fields are checked`() {
        val sales = loggedIn("perf.sales.0001")
        val client = ownClient(sales)
        fun post(changes: Map<String, Any?>) = sales.post(
            "/api/deals",
            mapOf("clientId" to client, "title" to "X", "value" to 100, "expectedClose" to LocalDate.now().toString()) + changes,
        )
        assertEquals(51191, post(mapOf("value" to -1))["errorNumber"])
        assertEquals(51191, post(mapOf("value" to 1.005))["errorNumber"])
        assertEquals(51196, post(mapOf("stage" to "WON"))["errorNumber"])
        assertEquals(400, post(mapOf("title" to " ")).status)
        val foreignOffer = loggedIn("perf.manager.0001").post("/api/offers", mapOf("clientId" to ownClient(loggedIn("perf.manager.0001")), "templateKey" to "IT")).body!!
        assertEquals(51194, loggedIn("perf.manager.0001").post(
            "/api/deals",
            mapOf("clientId" to client, "title" to "X", "value" to 1, "expectedClose" to LocalDate.now().toString(), "offerId" to foreignOffer["id"].asLong()),
        )["errorNumber"])
    }

    @Test
    fun `a salesperson sees only deals of own clients, a manager all`() {
        val other = loggedIn("perf.sales.0002")
        val foreign = deal(other, ownClient(other))
        val sales = loggedIn("perf.sales.0001")
        assertEquals(404, sales.get("/api/deals/${foreign["id"].asLong()}").status)
        assertEquals(51401, sales.post("/api/deals", mapOf("clientId" to foreign["clientId"].asLong(), "title" to "X", "value" to 1,
            "expectedClose" to LocalDate.now().toString()))["errorNumber"])
        assertTrue(sales.get("/api/deals").body!!.list().none { it["id"].asLong() == foreign["id"].asLong() })
        val manager = loggedIn("perf.manager.0001")
        val board = manager.get("/api/deals?ownerUserId=${foreign["ownerUserId"].asInt()}").body!!.list()
        assertTrue(board.any { it["id"].asLong() == foreign["id"].asLong() })
        assertTrue(board.all { it["ownerUserId"].asInt() == foreign["ownerUserId"].asInt() })
        // The manager opens a deal on the salesperson's client: the salesperson owns it.
        val forSales = deal(manager, foreign["clientId"].asLong())
        assertEquals(foreign["ownerUserId"].asInt(), forSales["ownerUserId"].asInt())
        assertEquals(51195, manager.get("/api/deals?scope=NOPE")["errorNumber"])
    }

    @Test
    fun `the seed fills the board`() {
        val board = loggedIn("perf.manager.0001").get("/api/deals").body!!.list()
        assertTrue(board.size >= 50, "seeded pipeline: ${board.size}")
        assertTrue(board.map { it["stage"].asString() }.toSet().containsAll(listOf("LEAD", "QUALIFIED", "PROPOSAL", "NEGOTIATION")))
        assertNull(board.firstOrNull { !it["closed"].asBoolean() && !it["closedAt"].isNull })
    }
}
