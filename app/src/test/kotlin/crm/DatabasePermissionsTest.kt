package crm

import crm.support.IntegrationTest
import crm.support.SqlServer
import org.junit.jupiter.api.Test
import java.sql.SQLException
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

/** ADR-0002: the application login can execute procedures of schema `app` and nothing else. */
class DatabasePermissionsTest : IntegrationTest() {

    private fun appExecute(sql: String) = SqlServer.app().use { it.createStatement().use { st -> st.execute(sql) } }

    @Test
    fun `application login cannot read a table`() {
        val error = assertFailsWith<SQLException> { appExecute("SELECT TOP 1 id FROM crm.clients") }
        assertEquals(229, error.errorCode)
    }

    @Test
    fun `application login cannot write a table`() {
        val error = assertFailsWith<SQLException> { appExecute("DELETE crm.project_comments WHERE id = -1") }
        assertEquals(229, error.errorCode)
    }

    @Test
    fun `application login cannot run the seed or internal helpers`() {
        assertEquals(229, assertFailsWith<SQLException> { appExecute("EXEC seed.run 1, 0, 0, 1, 'x'") }.errorCode)
        assertEquals(229, assertFailsWith<SQLException> { appExecute("EXEC crm.actor_require 1") }.errorCode)
    }

    @Test
    fun `application login can execute procedures of schema app`() {
        appExecute("EXEC app.health_ping")
    }

    @Test
    fun `procedure without actor is a host error 50001`() {
        val error = assertFailsWith<SQLException> { appExecute("EXEC app.client_get @actor_id = NULL, @id = 1") }
        assertEquals(50001, error.errorCode)
    }
}
