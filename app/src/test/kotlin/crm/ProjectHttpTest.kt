package crm

import crm.support.ApiClient
import crm.support.IntegrationTest
import crm.support.list
import org.junit.jupiter.api.Test
import tools.jackson.databind.JsonNode
import java.time.LocalDate
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ProjectHttpTest : IntegrationTest() {

    private fun userId(login: String) = scalar<Int>("SELECT id FROM crm.users WHERE login = ?", login)!!

    private fun teamOf(login: String) = scalar<Int>(
        "SELECT tm.team_id FROM crm.team_members tm JOIN crm.users u ON u.id = tm.user_id WHERE u.login = ?",
        login,
    )!!

    /** A new client of [login] (SALES) and a NEW project on it, owned by [login] in their team. */
    private fun newProject(c: ApiClient, login: String = "perf.sales.0001", due: LocalDate = LocalDate.now().plusDays(60)): JsonNode {
        val client = c.post(
            "/api/clients",
            mapOf("name" to "Test Projektowy ${System.nanoTime()}", "status" to "ACTIVE"),
        ).body!!
        val response = c.post(
            "/api/projects",
            mapOf(
                "clientId" to client["id"].asLong(), "teamId" to teamOf(login), "ownerUserId" to userId(login),
                "name" to "Test projekt", "startDate" to due.minusDays(30).toString(), "dueDate" to due.toString(),
                "budget" to 1234.56, "legalEntityId" to 1,
            ),
        )
        assertEquals(201, response.status, response.body.toString())
        return response.body!!
    }

    private fun changeStage(c: ApiClient, project: JsonNode, stage: String, comment: String? = null) =
        c.post(
            "/api/projects/${project["id"].asLong()}/stage",
            mapOf("stage" to stage, "comment" to comment, "rowVersion" to project["rowVersion"].asString()),
        )

    @Test
    fun `new project starts in NEW with one history row`() {
        val c = loggedIn("perf.sales.0001")
        val project = newProject(c)
        assertEquals("NEW", project["stage"].asString())
        val history = c.get("/api/projects/${project["id"].asLong()}/stages").body!!
        assertEquals(1, history.size())
        assertTrue(history[0]["fromStage"].isNull)
    }

    @Test
    fun `allowed stage change writes history and the optional comment in one go`() {
        val c = loggedIn("perf.sales.0001")
        val project = newProject(c)
        val id = project["id"].asLong()

        val accepted = changeStage(c, project, "ACCEPTED", "Test: offer accepted")
        assertEquals(200, accepted.status, accepted.body.toString())
        assertEquals("ACCEPTED", accepted.body!!["stage"].asString())

        val history = c.get("/api/projects/$id/stages").body!!
        assertEquals(listOf("ACCEPTED", "NEW"), history.list().map { it["toStage"].asString() })
        val comments = c.get("/api/projects/$id/comments").body!!["items"]
        assertEquals("Test: offer accepted", comments[0]["body"].asString())
    }

    @Test
    fun `stage change outside the transition table is 409`() {
        val c = loggedIn("perf.sales.0001")
        val response = changeStage(c, newProject(c), "CLOSED")
        assertEquals(409, response.status)
        assertEquals(51902, response.body!!["errorNumber"].asInt())
    }

    @Test
    fun `same stage is a no-op and stale rowVersion is 409`() {
        val c = loggedIn("perf.sales.0001")
        val project = newProject(c)
        val same = changeStage(c, project, "NEW", "Test: ignored")
        assertEquals(200, same.status)
        assertEquals(project["rowVersion"].asString(), same.body!!["rowVersion"].asString())
        assertEquals(0, c.get("/api/projects/${project["id"].asLong()}/comments").body!!["items"].size())

        assertEquals(200, changeStage(c, project, "ACCEPTED").status)
        val stale = changeStage(c, project, "DECLINED")
        assertEquals(409, stale.status)
        assertEquals(51901, stale.body!!["errorNumber"].asInt())
    }

    @Test
    fun `closed project cannot be edited`() {
        val c = loggedIn("perf.sales.0001")
        var p = newProject(c)
        for (stage in listOf("ACCEPTED", "ACTIVE", "CLOSED")) p = changeStage(c, p, stage).body!!
        val response = c.put(
            "/api/projects/${p["id"].asLong()}",
            mapOf(
                "teamId" to p["teamId"].asInt(), "ownerUserId" to p["ownerUserId"].asInt(), "name" to "Test changed",
                "startDate" to p["startDate"].asString(), "dueDate" to p["dueDate"].asString(),
                "budget" to 1, "legalEntityId" to p["legalEntityId"].asInt(), "rowVersion" to p["rowVersion"].asString(),
            ),
        )
        assertEquals(409, response.status)
        assertEquals(51902, response.body!!["errorNumber"].asInt())
    }

    @Test
    fun `owner must be a member of the project team`() {
        val c = loggedIn("perf.manager.0001")
        val client = scalar<Long>("SELECT TOP 1 id FROM crm.clients ORDER BY id")!!
        val otherTeam = teamOf("perf.sales.0002")
        val response = c.post(
            "/api/projects",
            mapOf(
                "clientId" to client, "teamId" to otherTeam, "ownerUserId" to userId("perf.sales.0001"),
                "name" to "Test", "startDate" to "2026-01-01", "dueDate" to "2026-02-01", "budget" to 10, "legalEntityId" to 1,
            ),
        )
        assertEquals(400, response.status)
        assertEquals(51037, response.body!!["errorNumber"].asInt())
    }

    @Test
    fun `sales user does not see projects of other teams and other clients`() {
        val foreign = newProject(loggedIn("perf.sales.0002"), "perf.sales.0002")
        assertTrue(teamOf("perf.sales.0001") != teamOf("perf.sales.0002"))
        val sales = loggedIn("perf.sales.0001")
        assertEquals(404, sales.get("/api/projects/${foreign["id"].asLong()}").status)
        val visibleIds = sales.get("/api/projects?size=200").body!!["items"].list().map { it["id"].asLong() }
        assertTrue(foreign["id"].asLong() !in visibleIds)
        // A team mate sees the project of their team.
        val mate = newProject(loggedIn("perf.sales.0003"), "perf.sales.0003")
        assertEquals(teamOf("perf.sales.0001"), teamOf("perf.sales.0003"))
        assertEquals(200, sales.get("/api/projects/${mate["id"].asLong()}").status)
    }

    @Test
    fun `overdue filter returns only open projects due before today, paged by due date`() {
        val c = loggedIn("perf.manager.0001")
        val today = LocalDate.now()
        val all = mutableListOf<JsonNode>()
        var cursor: String? = null
        do {
            val page = c.get("/api/projects?overdue=true&size=50" + (cursor?.let { "&cursor=$it" } ?: "")).body!!
            all += page["items"].list()
            cursor = page["nextCursor"].takeUnless { it == null || it.isNull }?.asString()
        } while (cursor != null)

        val expected = scalar<Int>(
            "SELECT COUNT(*) FROM crm.projects WHERE stage IN ('NEW','ACCEPTED','ACTIVE','ON_HOLD') " +
                "AND due_date < CAST(SYSUTCDATETIME() AS date)",
        )
        assertEquals(expected, all.size)
        assertTrue(all.all { it["overdue"].asBoolean() && LocalDate.parse(it["dueDate"].asString()) < today })
        val dues = all.map { it["dueDate"].asString() }
        assertEquals(dues.sorted(), dues)
    }

    @Test
    fun `count matches the list - all pages of a sales user and the overdue filter of a manager`() {
        val sales = loggedIn("perf.sales.0001")
        newProject(sales)
        var shown = 0
        var cursor: String? = null
        do {
            val page = sales.get("/api/projects?size=200" + (cursor?.let { "&cursor=$it" } ?: "")).body!!
            shown += page["items"].list().size
            cursor = page["nextCursor"].takeUnless { it == null || it.isNull }?.asString()
        } while (cursor != null)
        assertEquals(shown.toLong(), sales.get("/api/projects/count").body!!["total"].asLong())

        val manager = loggedIn("perf.manager.0001")
        val overdue = scalar<Long>(
            "SELECT COUNT_BIG(*) FROM crm.projects WHERE stage IN ('NEW','ACCEPTED','ACTIVE','ON_HOLD') " +
                "AND due_date < CAST(SYSUTCDATETIME() AS date)",
        )
        assertEquals(overdue, manager.get("/api/projects/count?overdue=true").body!!["total"].asLong())
        assertEquals(400, manager.get("/api/projects/count?stage=NOPE").status)
    }

    @Test
    fun `team statistics from the indexed view match the projects table`() {
        val c = loggedIn("perf.manager.0001")
        val team = teamOf("perf.sales.0001")
        newProject(loggedIn("perf.sales.0001")) // a write must be reflected immediately
        val stats = c.get("/api/teams/$team/stats").body!!
        val fromView = stats.list().sumOf { it["projectCount"].asLong() }
        val fromTable = scalar<Int>("SELECT COUNT(*) FROM crm.projects WHERE team_id = ?", team)!!.toLong()
        assertEquals(fromTable, fromView)
    }

    @Test
    fun `comments are paged newest first`() {
        val c = loggedIn("perf.sales.0001")
        val id = newProject(c)["id"].asLong()
        repeat(3) { assertEquals(201, c.post("/api/projects/$id/comments", mapOf("body" to "Test $it")).status) }
        val first = c.get("/api/projects/$id/comments?size=2").body!!
        assertEquals(listOf("Test 2", "Test 1"), first["items"].list().map { it["body"].asString() })
        val second = c.get("/api/projects/$id/comments?size=2&cursor=${first["nextCursor"].asString()}").body!!
        assertEquals(listOf("Test 0"), second["items"].list().map { it["body"].asString() })
        assertEquals(400, c.post("/api/projects/$id/comments", mapOf("body" to "   ")).status)
    }
}
