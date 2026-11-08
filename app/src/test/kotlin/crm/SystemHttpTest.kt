package crm

import crm.support.IntegrationTest
import crm.support.SqlServer
import crm.support.list
import org.junit.jupiter.api.Test
import org.slf4j.LoggerFactory
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** The application reports on itself (ADR-0012): HTTP answers, the log, the database, the queues - for admins. */
class SystemHttpTest : IntegrationTest() {

    private fun admin() = loggedIn(ADMIN_LOGIN, ADMIN_PASSWORD)

    @Test
    fun `system pages are for administrators only`() {
        val sales = loggedIn("perf.sales.0001")
        for (path in listOf("/api/system/status", "/api/system/requests", "/api/system/logs", "/api/system/database", "/api/system/queues")) {
            assertEquals(403, sales.get(path).status, path)
        }
        assertEquals(401, client().get("/api/system/status").status)
    }

    @Test
    fun `every answer is recorded with its status, path without the query and the user`() {
        val c = loggedIn("perf.manager.0001")
        assertEquals(404, c.get("/api/desk/tickets/999999999?secret=x").status)
        assertEquals(200, c.get("/api/clients?size=1").status)
        val a = admin()
        assertEquals(200, a.post("/api/system/jobs/writer/run", null).status)

        val notFound = a.get("/api/system/requests?outcome=NOT_FOUND&path=999999999").body!!["items"].list()
        val entry = notFound.first()
        assertEquals("/api/desk/tickets/999999999", entry["path"].asString(), "no query string")
        assertEquals(404, entry["status"].asInt())
        assertEquals("perf.manager.0001", entry["user"].asString())
        assertTrue(a.get("/api/system/requests?outcome=OK&path=/api/clients").body!!["items"].list().isNotEmpty())

        val status = a.get("/api/system/status?range=H24").body!!
        assertTrue(status["summary"]["total"].asLong() >= 2)
        assertTrue(status["summary"]["notFound"].asLong() >= 1)
        assertTrue(status["codes"].list().any { it["status"].asInt() == 404 })
        // The top ten failures depend on what other tests did before: only that they are failures.
        assertTrue(status["failing"].list().isNotEmpty() && status["failing"].list().all { it["status"].asInt() >= 400 })
        assertEquals("UP", status["database"].asString())
        assertEquals("UP", status["storage"].asString())
        assertTrue(status["settings"].list().any { it["variable"].asString() == "CRM_MONITORING_RETENTION" })
        assertTrue(status["settings"].list().none { it["variable"].asString().contains("PASSWORD") || it["variable"].asString().contains("SECRET") })
        assertEquals(400, a.get("/api/system/requests?outcome=NOPE").status)
    }

    @Test
    fun `log entries from INFO up go to the table`() {
        val marker = "test-log-${System.nanoTime()}"
        LoggerFactory.getLogger("crm.test.Probe").warn("Something to look at: {}", marker)
        val a = admin()
        a.post("/api/system/jobs/writer/run", null)
        val found = a.get("/api/system/logs?level=WARN&search=$marker").body!!["items"].list()
        assertEquals(1, found.size)
        assertEquals("WARN", found[0]["level"].asString())
        assertEquals("crm.test.Probe", found[0]["source"].asString())
        assertTrue(a.get("/api/system/logs?level=ERROR&search=$marker").body!!["items"].list().isEmpty())
    }

    @Test
    fun `the signed procedures see the whole server, the application login alone does not`() {
        val db = admin().get("/api/system/database").body!!
        assertTrue(db["overview"]["userSessions"].asInt() >= 2, "sessions of every login through the signature")
        // The pool alone keeps several sessions open; through the signature they are all visible.
        assertTrue(db["sessions"].list().size >= 2)
        assertTrue(db["tables"].list().any { it["table"].asString() == "tickets" && it["rows"].asLong() > 0 })
        assertTrue(db["overview"]["events"].asLong() > 0)
        // Without the signature the same login sees only its own session (no VIEW SERVER STATE).
        val own = SqlServer.app().use { c ->
            c.createStatement().use { st -> st.executeQuery("EXEC sp_executesql N'SELECT COUNT(*) FROM sys.dm_exec_sessions'").use { it.next(); it.getInt(1) } }
        }
        assertEquals(1, own)
    }

    @Test
    fun `queues and jobs, and the cleanup runs on demand`() {
        val a = admin()
        val ran = a.post("/api/system/jobs/cleanup/run", null).body!!
        assertTrue(ran["lastResult"].asString().contains("deleted"), ran.toString())
        val queues = a.get("/api/system/queues").body!!
        assertEquals(listOf("requests", "logs"), queues["queues"].list().map { it["name"].asString() })
        assertEquals(listOf("writer", "cleanup"), queues["jobs"].list().map { it["name"].asString() })
        assertEquals(404, a.post("/api/system/jobs/nope/run", null).status)
    }
}
