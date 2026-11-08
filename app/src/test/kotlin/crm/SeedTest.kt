package crm

import crm.support.IntegrationTest
import crm.support.SqlServer
import org.junit.jupiter.api.Test
import java.sql.SQLException
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

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
}
