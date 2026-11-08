package crm

import crm.support.IntegrationTest
import crm.support.SqlServer
import org.junit.jupiter.api.Test
import java.sql.SQLException
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/** The seed is the same procedure as in production, run here with small numbers. */
class SeedTest : IntegrationTest() {

    @Test
    fun `seed creates the requested rows, consistent with each other`() {
        assertEquals(9, scalar<Int>("SELECT COUNT(*) FROM crm.users WHERE login LIKE 'perf.%'"))
        assertEquals(2, scalar<Int>("SELECT COUNT(*) FROM crm.teams WHERE name LIKE N'Perf Team %'"))
        assertEquals(6, scalar<Int>("SELECT COUNT(*) FROM crm.team_members"))
        // Rows written by tests have created_by / own markers; seeded rows are counted by their seed markers.
        assertEquals(300, scalar<Int>("SELECT COUNT(*) FROM crm.clients WHERE email LIKE 'klient%@example.test'"))
        assertEquals(300, scalar<Int>("SELECT COUNT(*) FROM crm.projects WHERE created_by IS NULL"))
        assertEquals(300, scalar<Int>("SELECT COUNT(*) FROM crm.project_stage_history WHERE changed_by IS NULL"))
        assertEquals(100, scalar<Int>("SELECT COUNT(*) FROM crm.project_comments WHERE body NOT LIKE N'Test%'"))
    }

    @Test
    fun `every seeded project is owned by the client's sales user, a member of the project team`() {
        assertEquals(
            0,
            scalar<Int>(
                """
                SELECT COUNT(*) FROM crm.projects p
                JOIN crm.clients c ON c.id = p.client_id
                WHERE p.created_by IS NULL
                  AND (c.assigned_user_id <> p.owner_user_id
                       OR NOT EXISTS (SELECT 1 FROM crm.team_members tm
                                      WHERE tm.team_id = p.team_id AND tm.user_id = p.owner_user_id))
                """.trimIndent(),
            ),
        )
    }

    @Test
    fun `seed refuses to run twice`() {
        val error = assertFailsWith<SQLException> {
            SqlServer.migrator().use { it.createStatement().execute("EXEC seed.run 1, 0, 1, 1, 'x'") }
        }
        assertEquals(51060, error.errorCode)
    }

    @Test
    fun `invalid seed parameters are rejected`() {
        val error = assertFailsWith<SQLException> {
            SqlServer.migrator().use { it.createStatement().execute("EXEC seed.run -1, 0, 1, 1, 'x'") }
        }
        assertEquals(51050, error.errorCode)
    }

    @Test
    fun `seeded user logs in through the API`() {
        assertEquals("SALES", loggedIn("perf.sales.0001").get("/api/auth/me").body!!["role"].asString())
    }

    @Test
    fun `desk histories are replayed in the past, the read model matches the streams`() {
        // 238 stories; tests may add tickets later, never fewer.
        assertTrue(scalar<Int>("SELECT COUNT(*) FROM crm.tickets")!! >= 238)
        assertTrue(scalar<Int>("SELECT COUNT(*) FROM crm.tickets WHERE reported_at < DATEADD(DAY, -7, SYSUTCDATETIME())")!! > 50)
        assertEquals(0, scalar<Int>("SELECT COUNT(*) FROM crm.ticket_events WHERE at < DATEADD(DAY, -29, SYSUTCDATETIME())"))
        // The projection is the fold of the stream: its version is the last event's, its state follows the events.
        assertEquals(0, scalar<Int>(
            "SELECT COUNT(*) FROM crm.tickets t WHERE t.version <> (SELECT MAX(version) FROM crm.ticket_events e WHERE e.ticket_id = t.id)",
        ))
        assertEquals(0, scalar<Int>(
            "SELECT COUNT(*) FROM crm.tickets WHERE status = 'DONE' AND resolved_late <> IIF(resolved_at >= deadline, 1, 0)",
        ))
        assertEquals(0, scalar<Int>(
            "SELECT COUNT(*) FROM crm.tickets t WHERE t.comment_count <> " +
                "(SELECT COUNT(*) FROM crm.ticket_events e WHERE e.ticket_id = t.id AND e.event_type = 'TicketCommented')",
        ))
        // A curated story: taken, handed over, with its reason, hours ago.
        val handed = scalar<Int>(
            "SELECT COUNT(*) FROM crm.ticket_events e JOIN crm.tickets t ON t.id = e.ticket_id " +
                "WHERE t.title = N'Serwer plików nie odpowiada' AND e.event_type = 'TicketHandedOver' AND e.at < DATEADD(HOUR, -1, SYSUTCDATETIME())",
        )
        assertEquals(1, handed)
    }

    @Test
    fun `the application login cannot move the desk clock`() {
        val ticket = loggedIn("anna.nowak").post(
            "/api/desk/tickets",
            mapOf(
                "title" to "Test zegara", "description" to "Opis", "categoryKey" to "it", "subcategoryKey" to "it.hardware",
                "priority" to "LOW", "reportedAt" to java.time.Instant.now().toString(), "requesterIncognito" to true,
            ),
        ).body!!["id"].asLong()
        val anna = scalar<Int>("SELECT id FROM crm.users WHERE login = 'anna.nowak'")!!
        crm.support.SqlServer.app().use { c ->
            c.createStatement().use { st ->
                st.execute("EXEC sys.sp_set_session_context N'desk.now', '2020-01-01T00:00:00'")
                st.execute("EXEC app.desk_ticket_comment @actor_id = $anna, @ticket_id = $ticket, @text = N'Teraz'")
            }
        }
        assertEquals(0, scalar<Int>(
            "SELECT COUNT(*) FROM crm.ticket_events WHERE ticket_id = ? AND event_type = 'TicketCommented' AND at < '2021-01-01'",
            ticket,
        ))
    }
}
