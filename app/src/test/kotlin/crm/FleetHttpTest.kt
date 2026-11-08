package crm

import crm.support.ApiClient
import crm.support.IntegrationTest
import crm.support.list
import org.junit.jupiter.api.Test
import tools.jackson.databind.JsonNode
import java.time.LocalDate
import java.time.ZoneId
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** The fleet: cars, statuses, financing and handovers without overlaps (ADR-0018). */
class FleetHttpTest : IntegrationTest() {

    private operator fun crm.support.ApiResponse.get(key: String): Int? = body?.get(key)?.takeUnless { it.isNull }?.asInt()

    private val today: LocalDate get() = LocalDate.now(ZoneId.of("Europe/Warsaw"))

    private fun manager() = loggedIn("perf.manager.0001")

    /** A fresh person with no car: the seeded fleet hands cars to the seeded people. */
    private fun newPerson(): Int {
        val login = "driver.${System.nanoTime()}"
        val response = loggedIn(ADMIN_LOGIN, ADMIN_PASSWORD)
            .post("/api/users", mapOf("login" to login, "displayName" to "Kierowca $login", "role" to "SALES", "password" to PERF_PASSWORD))
        assertEquals(201, response.status, response.body.toString())
        return response.body!!["id"].asInt()
    }

    private fun newCar(c: ApiClient = manager(), plate: String = "TS ${System.nanoTime() % 100000}", vin: String? = null): JsonNode {
        val response = c.post(
            "/api/fleet/cars",
            mapOf("name" to "Toyota Corolla", "make" to "Toyota", "productionYear" to 2024, "plate" to plate, "vin" to vin, "legalEntityId" to 1),
        )
        assertEquals(201, response.status, response.body.toString())
        return response.body!!
    }

    private fun handOver(c: ApiClient, car: JsonNode, holder: Int, from: LocalDate, until: LocalDate?) = c.post(
        "/api/fleet/cars/${car["id"].asInt()}/handovers",
        mapOf("holderUserId" to holder, "issueDate" to from.toString(), "plannedReturn" to until?.toString(), "issueMileage" to 1000, "issueFuel" to 80),
    )

    @Test
    fun `a car - plate normalized and unique among cars in use, VIN once, managers only`() {
        val m = manager()
        val plate = "wa-${System.nanoTime() % 100000}"
        val car = newCar(m, plate)
        assertEquals(plate.uppercase(), car["plate"].asString())
        assertEquals("ACTIVE", car["status"].asString())
        assertEquals("FREE", car["availability"].asString())
        assertEquals(409, m.post("/api/fleet/cars", mapOf("name" to "X", "plate" to plate.replace("-", " ").uppercase(), "legalEntityId" to 1)).status)
        assertEquals(51222, m.post("/api/fleet/cars", mapOf("name" to "X", "plate" to "WA_1", "legalEntityId" to 1))["errorNumber"])
        assertEquals(51223, m.post("/api/fleet/cars", mapOf("name" to "X", "plate" to "TS 1", "vin" to "WVWZZZ1KZAW00000O", "legalEntityId" to 1))["errorNumber"])
        assertEquals(403, loggedIn("perf.sales.0001").post("/api/fleet/cars", mapOf("name" to "X", "plate" to "TS 2", "legalEntityId" to 1)).status)

        val vin = "WVWZZZ1KZAW${(System.nanoTime() % 1000000).toString().padStart(6, '0')}"
        fun put(c: ApiClient, car: JsonNode, vin: String?, reason: String? = null) = c.put(
            "/api/fleet/cars/${car["id"].asInt()}",
            mapOf("name" to "Toyota Corolla", "plate" to car["plate"].asString(), "vin" to vin, "legalEntityId" to 1,
                "vinReason" to reason, "rowVersion" to car["rowVersion"].asString()),
        )
        val withVin = put(m, car, vin).body!!
        assertEquals(vin, withVin["vin"].asString())
        val corrected = vin.dropLast(1) + "9"
        assertEquals(403, put(m, withVin, corrected, "literówka").status, "a VIN once given is the administrator's to correct")
        val admin = loggedIn(ADMIN_LOGIN, ADMIN_PASSWORD)
        assertEquals(51225, put(admin, withVin, corrected)["errorNumber"])
        assertEquals(corrected, put(admin, withVin, corrected, "literówka").body!!["vin"].asString())
    }

    @Test
    fun `statuses - a repair shop for the shop ones, dates in range, not for sale while handed over`() {
        val m = manager()
        val car = newCar(m)
        val id = car["id"].asInt()
        val shop = m.get("/api/fleet/partners?kind=REPAIR_SHOP").body!!.list().first()["id"].asInt()
        fun status(s: String, rv: String, extra: Map<String, Any?> = emptyMap()) =
            m.post("/api/fleet/cars/$id/status", mapOf("status" to s, "rowVersion" to rv) + extra)
        assertEquals(51228, status("IN_REPAIR_SHOP", car["rowVersion"].asString())["errorNumber"])
        assertEquals(51227, status("OPERATIONAL", car["rowVersion"].asString(), mapOf("effectiveOn" to today.plusDays(1).toString()))["errorNumber"])
        val inShop = status("IN_REPAIR_SHOP", car["rowVersion"].asString(), mapOf("repairShopId" to shop, "note" to "Wymiana opon")).body!!
        assertEquals(shop, inShop["repairShopId"].asInt())
        val ok = status("OPERATIONAL", inShop["rowVersion"].asString()).body!!
        assertTrue(ok["repairShopId"].isNull)
        assertEquals(listOf("OPERATIONAL", "IN_REPAIR_SHOP", "ACTIVE"),
            m.get("/api/fleet/cars/$id/status-history").body!!.list().map { it["status"].asString() })

        assertEquals(201, handOver(m, ok, newPerson(), today.plusDays(5), today.plusDays(9)).status)
        val fresh = m.get("/api/fleet/cars/$id").body!!
        assertEquals("FREE", fresh["availability"].asString(), "a planned handover leaves the car free today")
        assertTrue(fresh["holderPlanned"].asBoolean())
        assertEquals(51920, status("FOR_SALE", fresh["rowVersion"].asString())["errorNumber"])
        assertEquals(51922, m.delete("/api/fleet/cars/$id?rowVersion=${fresh["rowVersion"].asString()}")["errorNumber"])
    }

    @Test
    fun `financing - leasing ends at start plus months minus a day, money only for managers`() {
        val m = manager()
        val car = newCar(m)
        val leasing = m.get("/api/fleet/partners?kind=LEASING").body!!.list().first()["id"].asInt()
        val body = mapOf("financing" to "LEASING", "leasingId" to leasing, "instalment" to 1890.00, "currency" to "PLN",
            "leaseStart" to "2026-01-15", "leaseMonths" to 36, "contractNo" to "L/1/2026", "rowVersion" to car["rowVersion"].asString())
        assertEquals(51226, m.put("/api/fleet/cars/${car["id"].asInt()}/financing", body + ("leaseMonths" to 0))["errorNumber"])
        val financed = m.put("/api/fleet/cars/${car["id"].asInt()}/financing", body).body!!
        assertEquals("2029-01-14", financed["leaseEnd"].asString())
        val seenBySales = loggedIn("perf.sales.0001").get("/api/fleet/cars/${car["id"].asInt()}").body!!
        assertTrue(seenBySales["instalment"].isNull && seenBySales["contractNo"].isNull)
        assertEquals("2029-01-14", seenBySales["leaseEnd"].asString())
    }

    @Test
    fun `handovers - one per car and one car per person at a time, end day included`() {
        val m = manager()
        val car = newCar(m)
        val other = newCar(m)
        val anna = newPerson()
        val piotr = newPerson()
        val start = today.plusDays(100)
        assertEquals(201, handOver(m, car, anna, start, start.plusDays(10)).status)
        assertEquals(51923, handOver(m, car, piotr, start.plusDays(10), start.plusDays(12))["errorNumber"], "the 10th day is still taken")
        assertEquals(201, handOver(m, car, piotr, start.plusDays(11), null).status, "from the next day is fine")
        assertEquals(51923, handOver(m, car, anna, start.plusDays(200), start.plusDays(201))["errorNumber"], "open-ended blocks the future")
        assertEquals(51924, handOver(m, other, anna, start.plusDays(5), start.plusDays(6))["errorNumber"])
        assertEquals(51230, handOver(m, other, piotr, start, start.minusDays(1))["errorNumber"])
        assertTrue(m.get("/api/fleet/cars/${car["id"].asInt()}/handovers").body!!.list().all { it["state"].asString() == "PLANNED" })
    }

    @Test
    fun `return, undo on the same day, cancel with a reason, overdue shows`() {
        val m = manager()
        val car = newCar(m)
        val holder = newPerson()
        val h = handOver(m, car, holder, today.minusDays(10), today.minusDays(1)).body!!
        assertEquals("OVERDUE", h["state"].asString())
        assertEquals("OVERDUE", m.get("/api/fleet/cars/${car["id"].asInt()}").body!!["availability"].asString())
        assertTrue(m.get("/api/fleet/cars?availability=OVERDUE&search=${car["plate"].asString().replace(" ", "")}").body!!["items"].list().isNotEmpty())
        assertTrue(m.get("/api/fleet/cars/${car["id"].asInt()}/handovers").body!!.list().any { it["id"].asLong() == h["id"].asLong() })

        fun back(on: LocalDate, mileage: Int, rv: String) = m.post("/api/fleet/handovers/${h["id"].asLong()}/return",
            mapOf("returnedOn" to on.toString(), "returnMileage" to mileage, "returnFuel" to 40, "rowVersion" to rv))
        assertEquals(51232, back(today.plusDays(1), 1500, h["rowVersion"].asString())["errorNumber"])
        assertEquals(51233, back(today, 999, h["rowVersion"].asString())["errorNumber"])
        val returned = back(today, 1500, h["rowVersion"].asString()).body!!
        assertEquals("RETURNED", returned["state"].asString())
        val undone = m.post("/api/fleet/handovers/${h["id"].asLong()}/undo-return", mapOf("rowVersion" to returned["rowVersion"].asString())).body!!
        assertEquals("OVERDUE", undone["state"].asString())

        val cancel = "/api/fleet/handovers/${h["id"].asLong()}/cancel"
        assertEquals(400, m.post(cancel, mapOf("reason" to " ", "rowVersion" to undone["rowVersion"].asString())).status)
        val cancelled = m.post(cancel, mapOf("reason" to "Pomyłka", "rowVersion" to undone["rowVersion"].asString())).body!!
        assertEquals("CANCELLED", cancelled["state"].asString())
        assertEquals("FREE", m.get("/api/fleet/cars/${car["id"].asInt()}").body!!["availability"].asString())
    }

    @Test
    fun `partners unique per kind ignoring case and Polish letters, the seeded fleet`() {
        val m = manager()
        val name = "Serwis Łódź ${System.nanoTime()}"
        assertEquals(201, m.post("/api/fleet/partners", mapOf("kind" to "REPAIR_SHOP", "name" to name)).status)
        assertEquals(409, m.post("/api/fleet/partners", mapOf("kind" to "REPAIR_SHOP", "name" to name.replace("Łódź", "lodz").uppercase())).status)
        assertEquals(201, m.post("/api/fleet/partners", mapOf("kind" to "LEASING", "name" to name)).status)

        val cars = m.get("/api/fleet/cars?size=200").body!!
        assertTrue(cars["items"].list().isNotEmpty())
        assertTrue(m.get("/api/fleet/cars?availability=HANDED_OVER").body!!["items"].list().isNotEmpty())
        assertTrue(m.get("/api/fleet/statuses").body!!.list().size == 7)
    }
}
