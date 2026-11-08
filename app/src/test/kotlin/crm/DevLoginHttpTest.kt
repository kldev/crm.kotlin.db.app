package crm

import crm.support.IntegrationTest
import org.junit.jupiter.api.Test
import org.springframework.test.context.TestPropertySource
import kotlin.test.assertEquals

@TestPropertySource(properties = ["crm.auth.dev-login=true"])
class DevLoginHttpTest : IntegrationTest() {

    @Test
    fun `dev login starts a session for an active user without a password`() {
        val c = client()
        assertEquals(true, c.get("/api/auth/dev-login").body!!["enabled"].asBoolean())
        c.csrf()
        val response = c.post("/api/auth/dev-login", mapOf("login" to "perf.manager.0001"))
        assertEquals(200, response.status, response.body.toString())
        assertEquals("MANAGER", response.body!!["role"].asString())
        assertEquals("perf.manager.0001", c.get("/api/auth/me").body!!["login"].asString())
        // Roles still apply: a manager may read users but not create them.
        assertEquals(403, c.post("/api/users", mapOf("login" to "x")).status)
    }

    @Test
    fun `dev login rejects an unknown login and still needs the CSRF header`() {
        val c = client()
        c.csrf()
        assertEquals(401, c.post("/api/auth/dev-login", mapOf("login" to "nobody.here")).status)
        assertEquals(403, client().post("/api/auth/dev-login", mapOf("login" to "perf.sales.0001"), withCsrf = false).status)
    }
}
