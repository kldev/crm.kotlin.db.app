package crm

import crm.support.ApiClient
import crm.support.IntegrationTest
import crm.support.list
import org.junit.jupiter.api.Test
import tools.jackson.databind.JsonNode
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** A salesperson's day: activities, the next step and tasks of a deal (ADR-0017). */
class SalesWorkspaceHttpTest : IntegrationTest() {

    private operator fun crm.support.ApiResponse.get(key: String): Int? = body?.get(key)?.takeUnless { it.isNull }?.asInt()

    private fun me(c: ApiClient) = c.get("/api/auth/me").body!!["id"].asInt()

    private fun deal(c: ApiClient): JsonNode {
        val client = c.post("/api/clients", mapOf("name" to "Test Dzień ${System.nanoTime()}", "status" to "ACTIVE")).body!!["id"].asLong()
        return c.post(
            "/api/deals",
            mapOf("clientId" to client, "title" to "Wdrożenie", "value" to 1000, "expectedClose" to LocalDate.now().plusDays(20).toString()),
        ).body!!
    }

    @Test
    fun `activities are logged, checked and keep the newest on the deal`() {
        val c = loggedIn("perf.sales.0001")
        val d = deal(c)
        val id = d["id"].asLong()
        assertEquals(listOf("CALL", "EMAIL", "MEETING", "PRESENTATION", "NOTE", "TASK", "OTHER"),
            c.get("/api/deals/activity-types").body!!.list().map { it["type"].asString() })
        assertEquals(51210, c.post("/api/deals/$id/activities", mapOf("type" to "FAX", "note" to "x"))["errorNumber"])
        assertEquals(51212, c.post("/api/deals/$id/activities", mapOf("type" to "CALL", "note" to "x",
            "occurredAt" to Instant.now().plus(1, ChronoUnit.DAYS).toString()))["errorNumber"])
        assertEquals(201, c.post("/api/deals/$id/activities", mapOf("type" to "CALL", "note" to "Rozmowa")).status)
        val yesterday = Instant.now().minus(1, ChronoUnit.DAYS).truncatedTo(ChronoUnit.SECONDS)
        c.post("/api/deals/$id/activities", mapOf("type" to "EMAIL", "note" to "Wcześniej", "occurredAt" to yesterday.toString()))
        val log = c.get("/api/deals/$id/activities").body!!.list()
        assertEquals(listOf("CALL", "EMAIL"), log.map { it["type"].asString() })
        assertEquals(yesterday, Instant.parse(log[1]["occurredAt"].asString()))
        assertEquals("CALL", c.get("/api/deals/$id").body!!["lastActivityType"].asString(), "a backdated one does not move it back")
        assertEquals(404, loggedIn("perf.sales.0002").get("/api/deals/$id/activities").status)
    }

    @Test
    fun `the next step - both or neither, open deals only, due ones on my day`() {
        val c = loggedIn("perf.sales.0001")
        val d = deal(c)
        val id = d["id"].asLong()
        val at = Instant.now().minus(2, ChronoUnit.HOURS).truncatedTo(ChronoUnit.SECONDS)
        assertEquals(51213, c.put("/api/deals/$id/next-step", mapOf("nextStep" to "Zadzwonić", "rowVersion" to d["rowVersion"].asString()))["errorNumber"])
        val set = c.put("/api/deals/$id/next-step", mapOf("nextStep" to "Zadzwonić", "nextStepAt" to at.toString(), "rowVersion" to d["rowVersion"].asString())).body!!
        assertEquals(at, Instant.parse(set["nextStepAt"].asString()))
        val due = c.get("/api/sales/follow-ups?until=${Instant.now()}").body!!.list().map { it["id"].asLong() }
        assertTrue(id in due)
        assertTrue(id !in c.get("/api/sales/without-next-step").body!!.list().map { it["id"].asLong() })
        assertTrue(id !in c.get("/api/sales/follow-ups?until=${at.minus(1, ChronoUnit.HOURS)}").body!!.list().map { it["id"].asLong() })

        val won = c.post("/api/deals/$id/move", mapOf("stage" to "WON", "rowVersion" to set["rowVersion"].asString())).body!!
        assertTrue(won["nextStep"].isNull, "a closed deal has no next step")
        assertEquals(51909, c.put("/api/deals/$id/next-step", mapOf("nextStep" to "X", "nextStepAt" to at.toString(), "rowVersion" to won["rowVersion"].asString()))["errorNumber"])
    }

    @Test
    fun `a task of a deal takes its client, sits on my agenda and is logged on the deal when done`() {
        val c = loggedIn("perf.sales.0001")
        val d = deal(c)
        val today = LocalDate.now()
        val otherClient = c.post("/api/clients", mapOf("name" to "Test Inny ${System.nanoTime()}", "status" to "ACTIVE")).body!!["id"].asLong()
        fun post(extra: Map<String, Any?>) = c.post("/api/tasks", mapOf("title" to "Wysłać ofertę", "assigneeUserId" to me(c),
            "startDate" to today.minusDays(3).toString(), "endDate" to today.minusDays(1).toString(), "dealId" to d["id"].asLong()) + extra)
        assertEquals(51214, post(mapOf("clientId" to otherClient))["errorNumber"])
        val other = loggedIn("perf.sales.0002")
        assertEquals(51407, other.post("/api/tasks", mapOf("title" to "X", "assigneeUserId" to me(other), "startDate" to today.toString(),
            "endDate" to today.toString(), "dealId" to d["id"].asLong()))["errorNumber"])
        val task = post(emptyMap()).body!!
        assertEquals(d["clientId"].asLong(), task["clientId"].asLong())
        assertEquals("Wdrożenie", task["dealTitle"].asString())

        val agenda = c.get("/api/tasks/agenda?until=$today").body!!.list()
        assertTrue(agenda.any { it["id"].asLong() == task["id"].asLong() }, "an overdue task stays on the agenda")
        val since = Instant.now().minusSeconds(5)
        c.post("/api/tasks/${task["id"].asLong()}/done", mapOf("done" to true, "rowVersion" to task["rowVersion"].asString()))
        val log = c.get("/api/deals/${d["id"].asLong()}/activities").body!!.list()
        assertEquals("TASK", log.first()["type"].asString())
        assertTrue("Wysłać ofertę" in log.first()["note"].asString())
        val after = c.get("/api/tasks/agenda?until=$today&doneSince=$since").body!!.list().first { it["id"].asLong() == task["id"].asLong() }
        assertTrue(after["done"].asBoolean())
    }

    @Test
    fun `the seed gives salespeople a day`() {
        val c = loggedIn("perf.sales.0001")
        val until = Instant.now().plus(1, ChronoUnit.DAYS)
        assertTrue(c.get("/api/sales/follow-ups?until=$until").body!!.list().isNotEmpty())
        val manager = loggedIn("perf.manager.0001")
        val board = manager.get("/api/deals").body!!.list()
        assertTrue(board.count { !it["lastActivityAt"].isNull } > board.size / 2)
    }
}
