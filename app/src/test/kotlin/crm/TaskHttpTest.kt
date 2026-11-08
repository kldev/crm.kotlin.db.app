package crm

import crm.support.ApiClient
import crm.support.IntegrationTest
import crm.support.list
import org.junit.jupiter.api.Test
import tools.jackson.databind.JsonNode
import java.time.LocalDate
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Tasks on the calendar and the timeline, "mine" and "my department" (ADR-0014). */
class TaskHttpTest : IntegrationTest() {

    private operator fun crm.support.ApiResponse.get(key: String): Int? = body?.get(key)?.takeUnless { it.isNull }?.asInt()

    private fun me(c: ApiClient) = c.get("/api/auth/me").body!!["id"].asInt()

    private fun task(c: ApiClient, assignee: Int, start: LocalDate, end: LocalDate, title: String = "Test zadanie ${System.nanoTime()}"): JsonNode {
        val response = c.post(
            "/api/tasks",
            mapOf("title" to title, "assigneeUserId" to assignee, "startDate" to start.toString(), "endDate" to end.toString()),
        )
        assertEquals(201, response.status, response.body.toString())
        return response.body!!
    }

    private fun window(c: ApiClient, from: LocalDate, to: LocalDate, extra: String = "") =
        c.get("/api/tasks?from=$from&to=$to$extra").body!!.list()

    @Test
    fun `the window returns every task that overlaps it, by start date`() {
        val anna = loggedIn("anna.nowak")
        val day = LocalDate.now().plusYears(2).withDayOfMonth(10)
        val before = task(anna, me(anna), day.minusDays(5), day.minusDays(1))
        val across = task(anna, me(anna), day.minusDays(2), day.plusDays(2))
        val inside = task(anna, me(anna), day.plusDays(3), day.plusDays(4))
        val ids = window(anna, day, day.plusDays(6)).map { it["id"].asLong() }
        assertTrue(across["id"].asLong() in ids && inside["id"].asLong() in ids)
        assertTrue(before["id"].asLong() !in ids)
        assertEquals(51181, anna.get("/api/tasks?from=$day&to=${day.minusDays(1)}")["errorNumber"])
        assertEquals(51181, anna.get("/api/tasks?from=$day&to=${day.plusDays(200)}")["errorNumber"])
    }

    @Test
    fun `mine and my department`() {
        val anna = loggedIn("anna.nowak") // IT
        val piotr = loggedIn("piotr.kowalski") // IT
        val agnieszka = loggedIn("agnieszka.zielinska") // Kadry
        val day = LocalDate.now().plusYears(3)
        val annas = task(anna, me(anna), day, day)
        val piotrs = task(piotr, me(piotr), day, day)
        val hr = task(agnieszka, me(agnieszka), day, day)

        val mine = window(anna, day, day, "&scope=MINE").map { it["id"].asLong() }
        assertEquals(listOf(annas["id"].asLong()), mine)
        val department = window(anna, day, day, "&scope=DEPARTMENT").map { it["id"].asLong() }
        assertEquals(setOf(annas["id"].asLong(), piotrs["id"].asLong()), department.toSet())
        assertTrue(hr["id"].asLong() !in department)
        val kadry = window(anna, day, day, "&scope=ALL&department=Kadry").map { it["id"].asLong() }
        assertEquals(listOf(hr["id"].asLong()), kadry)
        assertEquals(51183, anna.get("/api/tasks?from=$day&to=$day&department=Nope")["errorNumber"])
        assertEquals("IT", annas["assigneeDepartment"].asString())
    }

    @Test
    fun `rules - fields, who may change a task, rowVersion, done and delete`() {
        val anna = loggedIn("anna.nowak")
        val day = LocalDate.now()
        fun post(changes: Map<String, Any?>) = anna.post(
            "/api/tasks",
            mapOf("title" to "Test", "assigneeUserId" to me(anna), "startDate" to day.toString(), "endDate" to day.toString()) + changes,
        )
        assertEquals(51181, post(mapOf("endDate" to day.minusDays(1).toString()))["errorNumber"])
        assertEquals(51402, post(mapOf("assigneeUserId" to 999999))["errorNumber"])
        assertEquals(400, post(mapOf("title" to " ")).status)

        val t = task(anna, me(anna), day, day.plusDays(2))
        val other = loggedIn("perf.sales.0003")
        val body = mapOf(
            "title" to "Przesunięte", "assigneeUserId" to me(anna), "startDate" to day.plusDays(5).toString(),
            "endDate" to day.plusDays(6).toString(), "rowVersion" to t["rowVersion"].asString(),
        )
        assertEquals(51304, other.put("/api/tasks/${t["id"].asLong()}", body)["errorNumber"])
        val moved = loggedIn("perf.manager.0001").put("/api/tasks/${t["id"].asLong()}", body).body!!
        assertEquals(day.plusDays(5).toString(), moved["startDate"].asString())
        assertEquals(409, anna.put("/api/tasks/${t["id"].asLong()}", body).status, "stale rowVersion")

        val done = anna.post("/api/tasks/${t["id"].asLong()}/done", mapOf("done" to true, "rowVersion" to moved["rowVersion"].asString())).body!!
        assertTrue(done["done"].asBoolean())
        assertTrue(window(anna, day.plusDays(5), day.plusDays(5), "&done=false").none { it["id"].asLong() == t["id"].asLong() })
        assertEquals(204, anna.delete("/api/tasks/${t["id"].asLong()}?rowVersion=${done["rowVersion"].asString()}").status)
        assertEquals(404, anna.get("/api/tasks/${t["id"].asLong()}").status)
    }

    @Test
    fun `departments - the list, set by an administrator only`() {
        val anna = loggedIn("anna.nowak")
        val departments = anna.get("/api/departments").body!!.list()
        assertTrue(departments.any { it["name"].asString() == "IT" && it["users"].asInt() >= 3 })
        val sales = loggedIn("perf.sales.0004")
        val salesId = me(sales)
        assertEquals(403, anna.put("/api/users/$salesId/department", mapOf("department" to "IT")).status)
        val admin = loggedIn(ADMIN_LOGIN, ADMIN_PASSWORD)
        assertEquals(51183, admin.put("/api/users/$salesId/department", mapOf("department" to "Nope"))["errorNumber"])
        assertEquals("Sprzedaż", admin.put("/api/users/$salesId/department", mapOf("department" to "Sprzedaż")).body!!["department"].asString())
        assertTrue(admin.get("/api/users?size=200").body!!["items"].list().any { it["id"].asInt() == salesId && it["department"].asString() == "Sprzedaż" })
    }

    @Test
    fun `the seed plans tasks around today`() {
        val anna = loggedIn("anna.nowak")
        val today = LocalDate.now()
        val plan = window(anna, today.minusDays(21), today.plusDays(35))
        assertTrue(plan.size >= 50, "seeded plan")
        assertTrue(plan.any { it["done"].asBoolean() } && plan.any { !it["done"].asBoolean() })
    }
}
