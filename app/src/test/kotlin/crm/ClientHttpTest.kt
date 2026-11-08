package crm

import crm.support.IntegrationTest
import crm.support.list
import org.junit.jupiter.api.Test
import kotlin.random.Random
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class ClientHttpTest : IntegrationTest() {

    private fun nip() = (1_900_000_000L + Random.nextLong(99_999_999)).toString()

    private fun clientBody(name: String = "Test Klient ${Random.nextInt()}", nip: String? = nip()) = mapOf(
        "name" to name, "nip" to nip, "email" to "test.${Random.nextInt(1_000_000)}@example.test",
        "phone" to "+48 500 000 000", "city" to "Poznań", "status" to "LEAD", "note" to "Test note",
    )

    @Test
    fun `create, read, update with rowVersion, stale rowVersion is 409`() {
        val c = loggedIn("perf.sales.0001")
        val created = c.post("/api/clients", clientBody())
        assertEquals(201, created.status, created.body.toString())
        val id = created.body!!["id"].asLong()
        assertEquals("perf.sales.0001", created.body!!["assignedUserLogin"].asString())

        val read = c.get("/api/clients/$id").body!!
        val v1 = read["rowVersion"].asString()
        val update = clientBody(name = "Test Renamed").plus("rowVersion" to v1).plus("assignedUserId" to read["assignedUserId"].asInt())
        val updated = c.put("/api/clients/$id", update)
        assertEquals(200, updated.status, updated.body.toString())
        assertEquals("Test Renamed", updated.body!!["name"].asString())
        assertNotEquals(v1, updated.body!!["rowVersion"].asString())

        val stale = c.put("/api/clients/$id", update)
        assertEquals(409, stale.status)
        assertEquals(51901, stale.body!!["errorNumber"].asInt())
    }

    @Test
    fun `update with identical values does not change rowVersion`() {
        val c = loggedIn("perf.sales.0001")
        val created = c.post("/api/clients", clientBody()).body!!
        val same = mapOf(
            "name" to created["name"].asString(), "nip" to created["nip"].asString(),
            "email" to created["email"].asString(), "phone" to created["phone"].asString(),
            "city" to created["city"].asString(), "status" to created["status"].asString(),
            "assignedUserId" to created["assignedUserId"].asInt(), "note" to created["note"].asString(),
            "rowVersion" to created["rowVersion"].asString(),
        )
        val response = c.put("/api/clients/${created["id"].asLong()}", same)
        assertEquals(200, response.status)
        assertEquals(created["rowVersion"].asString(), response.body!!["rowVersion"].asString())
    }

    @Test
    fun `rules of the procedure come back as 400 with the error number`() {
        val c = loggedIn("perf.sales.0001")
        val badNip = c.post("/api/clients", clientBody(nip = "12345"))
        assertEquals(400, badNip.status)
        assertEquals(51011, badNip.body!!["errorNumber"].asInt())

        val blank = c.post("/api/clients", clientBody(name = ""))
        assertEquals(400, blank.status) // request validation, before the database
    }

    @Test
    fun `duplicate NIP is a conflict`() {
        val c = loggedIn("perf.manager.0001")
        val nip = nip()
        assertEquals(201, c.post("/api/clients", clientBody(nip = nip)).status)
        assertEquals(409, c.post("/api/clients", clientBody(nip = nip)).status)
    }

    @Test
    fun `sales user sees only own clients and cannot assign to others`() {
        val other = loggedIn("perf.sales.0002")
        val foreign = other.post("/api/clients", clientBody()).body!!["id"].asLong()

        val sales = loggedIn("perf.sales.0001")
        assertEquals(404, sales.get("/api/clients/$foreign").status)
        val me = sales.get("/api/auth/me").body!!["id"].asInt()
        val page = sales.get("/api/clients?size=200").body!!
        assertTrue(page["items"].list().all { it["assignedUserId"].asInt() == me })

        val assignOther = sales.post("/api/clients", clientBody().plus("assignedUserId" to me + 1))
        assertEquals(403, assignOther.status)
        assertEquals(51303, assignOther.body!!["errorNumber"].asInt())
    }

    @Test
    fun `keyset pages do not overlap and follow the name order`() {
        val c = loggedIn("perf.manager.0001")
        val first = c.get("/api/clients?size=5").body!!
        val second = c.get("/api/clients?size=5&cursor=${first["nextCursor"].asString()}").body!!
        val ids1 = first["items"].list().map { it["id"].asLong() }
        val ids2 = second["items"].list().map { it["id"].asLong() }
        assertEquals(5, ids2.size)
        assertTrue(ids1.intersect(ids2.toSet()).isEmpty())
        assertTrue(ids1.min() > ids2.max(), "newest first")

        // Name mode: (name, id) keyset; every row matches the prefix and pages do not overlap.
        val byName1 = c.get("/api/clients?namePrefix=Z&size=5").body!!
        val byName2 = c.get("/api/clients?namePrefix=Z&size=5&cursor=${byName1["nextCursor"].asString()}").body!!
        val rows = byName1["items"].list() + byName2["items"].list()
        assertEquals(10, rows.size)
        assertTrue(rows.all { it["name"].asString().startsWith("Z") })
        assertEquals(10, rows.map { it["id"].asLong() }.toSet().size)
    }

    @Test
    fun `invalid cursor and page size are 400`() {
        val c = loggedIn("perf.manager.0001")
        assertEquals(400, c.get("/api/clients?cursor=%21%21%21").status)
        assertEquals(400, c.get("/api/clients?size=500").status)
    }

    @Test
    fun `delete - sales forbidden, client with projects is a conflict, manager deletes a client without projects`() {
        val sales = loggedIn("perf.sales.0001")
        val own = sales.post("/api/clients", clientBody()).body!!
        assertEquals(403, sales.delete("/api/clients/${own["id"].asLong()}?rowVersion=${own["rowVersion"].asString()}").status)

        val manager = loggedIn("perf.manager.0001")
        val withProjects = scalar<Long>("SELECT TOP 1 client_id FROM crm.projects")!!
        val rv = manager.get("/api/clients/$withProjects").body!!["rowVersion"].asString()
        val conflict = manager.delete("/api/clients/$withProjects?rowVersion=$rv")
        assertEquals(409, conflict.status)
        assertEquals(51904, conflict.body!!["errorNumber"].asInt())

        assertEquals(204, manager.delete("/api/clients/${own["id"].asLong()}?rowVersion=${own["rowVersion"].asString()}").status)
        assertEquals(404, manager.get("/api/clients/${own["id"].asLong()}").status)
    }
}
