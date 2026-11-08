package crm

import crm.support.IntegrationTest
import org.junit.jupiter.api.Test
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class AuthHttpTest : IntegrationTest() {

    private fun newUser(role: String = "SALES", password: String = "Start-Passw0rd"): String {
        val login = "t.${UUID.randomUUID().toString().take(8)}"
        val created = loggedIn(ADMIN_LOGIN, ADMIN_PASSWORD)
            .post("/api/users", mapOf("login" to login, "displayName" to "Test $login", "role" to role, "password" to password))
        assertEquals(201, created.status, created.body.toString())
        return login
    }

    @Test
    fun `wrong password, unknown login and empty body are rejected without detail`() {
        val c = client()
        val wrong = c.login("perf.sales.0001", "not-the-password")
        val unknown = c.login("nobody.here", "whatever-123")
        assertEquals(401, wrong.status)
        assertEquals(401, unknown.status)
        assertEquals(wrong.body!!["detail"], unknown.body!!["detail"])
        assertEquals(400, c.post("/api/auth/login", mapOf("login" to "")).status)
    }

    @Test
    fun `account is locked after the configured number of failures, even for the right password`() {
        val login = newUser()
        val c = client()
        repeat(MAX_FAILED) { assertEquals(401, c.login(login, "wrong-password").status) }
        assertEquals(401, c.login(login, "Start-Passw0rd").status)
        val lockedUntil = scalar<Any>("SELECT locked_until FROM crm.users WHERE login = ?", login)
        assertTrue(lockedUntil != null, "locked_until must be set")
    }

    @Test
    fun `successful login resets the failure counter`() {
        val login = newUser()
        val c = client()
        repeat(MAX_FAILED - 1) { c.login(login, "wrong-password") }
        assertEquals(200, c.login(login, "Start-Passw0rd").status)
        assertEquals(0, scalar<Int>("SELECT failed_login_count FROM crm.users WHERE login = ?", login))
    }

    @Test
    fun `deactivated user cannot log in`() {
        val login = newUser()
        val id = scalar<Int>("SELECT id FROM crm.users WHERE login = ?", login)!!
        assertEquals(200, loggedIn(ADMIN_LOGIN, ADMIN_PASSWORD).put("/api/users/$id/active", mapOf("active" to false)).status)
        assertEquals(401, client().login(login, "Start-Passw0rd").status)
    }

    @Test
    fun `api requires a session`() {
        assertEquals(401, client().get("/api/clients").status)
        assertEquals(401, client().get("/api/auth/me").status)
    }

    @Test
    fun `writes require the CSRF header`() {
        val c = loggedIn("perf.sales.0001")
        val without = c.post("/api/projects/1/comments", mapOf("body" to "Test no csrf"), withCsrf = false)
        assertEquals(403, without.status)
    }

    @Test
    fun `session id changes on login and logout ends the session`() {
        val c = client()
        c.csrf()
        c.get("/api/auth/me") // anonymous request
        assertEquals(200, c.login("perf.sales.0002", PERF_PASSWORD).status)
        assertEquals(200, c.get("/api/auth/me").status)
        assertEquals(204, c.post("/api/auth/logout", null).status)
        assertEquals(401, c.get("/api/auth/me").status)
    }

    @Test
    fun `roles are enforced by the endpoint and by the procedure`() {
        val sales = loggedIn("perf.sales.0001")
        assertEquals(403, sales.get("/api/users").status)
        val manager = loggedIn("perf.manager.0001")
        assertEquals(200, manager.get("/api/users").status)
        assertEquals(403, manager.post("/api/users", mapOf("login" to "x.y.z", "displayName" to "X", "role" to "SALES", "password" to "Passw0rd-123")).status)
    }

    @Test
    fun `admin cannot deactivate or demote themselves`() {
        val admin = loggedIn(ADMIN_LOGIN, ADMIN_PASSWORD)
        val me = admin.get("/api/auth/me").body!!["id"].asInt()
        val response = admin.put("/api/users/$me/role", mapOf("role" to "SALES"))
        assertEquals(400, response.status)
        assertEquals(51018, response.body!!["errorNumber"].asInt())
    }

    @Test
    fun `user changes own password with the current one`() {
        val login = newUser()
        val c = loggedIn(login, "Start-Passw0rd")
        assertEquals(400, c.post("/api/auth/password", mapOf("currentPassword" to "bad", "newPassword" to "New-Passw0rd-1")).status)
        assertEquals(204, c.post("/api/auth/password", mapOf("currentPassword" to "Start-Passw0rd", "newPassword" to "New-Passw0rd-1")).status)
        assertEquals(401, client().login(login, "Start-Passw0rd").status)
        assertNotEquals(401, client().login(login, "New-Passw0rd-1").status)
    }
}
