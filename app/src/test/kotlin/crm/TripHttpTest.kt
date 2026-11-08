package crm

import crm.support.ApiClient
import crm.support.IntegrationTest
import crm.support.list
import org.junit.jupiter.api.Test
import tools.jackson.databind.JsonNode
import java.math.BigDecimal
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Business trips and their settlement under the Polish rules (ADR-0019). */
class TripHttpTest : IntegrationTest() {

    private operator fun crm.support.ApiResponse.get(key: String): Int? = body?.get(key)?.takeUnless { it.isNull }?.asInt()

    private val start: Instant = Instant.parse("2026-10-05T06:00:00Z")

    private fun client(c: ApiClient) =
        c.post("/api/clients", mapOf("name" to "Test Delegacja ${System.nanoTime()}", "city" to "Łódź", "status" to "ACTIVE")).body!!["id"].asLong()

    private fun body(hours: Long, extra: Map<String, Any?> = emptyMap(), from: Instant = start) = mapOf(
        "purpose" to "OTHER", "destination" to "Łódź", "country" to "PL", "startsAt" to from.toString(),
        "endsAt" to from.plus(hours, ChronoUnit.HOURS).toString(), "transport" to "TRAIN",
    ) + extra

    private fun trip(c: ApiClient, hours: Long, extra: Map<String, Any?> = emptyMap(), from: Instant = start): JsonNode {
        val response = c.post("/api/trips", body(hours, extra, from))
        assertEquals(201, response.status, response.body.toString())
        return response.body!!
    }

    private fun amount(node: JsonNode, field: String) = BigDecimal(node[field].asString())

    private fun assertAmount(expected: String, node: JsonNode, field: String) =
        assertEquals(0, BigDecimal(expected).compareTo(amount(node, field)), "$field: ${node[field]}")

    @Test
    fun `domestic per diems by the length of the trip, meals, lump sums and mileage`() {
        val c = loggedIn("perf.sales.0001")
        assertAmount("0", trip(c, 7), "dietAmount")
        assertAmount("22.50", trip(c, 10), "dietAmount")
        assertAmount("45.00", trip(c, 13), "dietAmount")
        val long = trip(c, 53, mapOf("lumpNights" to 1, "localTransport" to true))
        assertAmount("2.50", long, "diets")
        assertAmount("112.50", long, "dietAmount")
        assertAmount("94.50", long, "lumpAmount") // a night 67.50 + local transport 3 started days x 9
        val lunch = trip(c, 13, mapOf("lunches" to 1))
        assertAmount("22.50", lunch, "mealDeduction")
        assertAmount("22.50", lunch, "total")
        val car = trip(c, 9, mapOf("transport" to "PRIVATE_CAR", "vehicle" to "CAR_GT_900", "kilometres" to 100))
        assertAmount("115.00", car, "mileageAmount")
        assertEquals("PLN", car["currency"].asString())
    }

    @Test
    fun `abroad - a third for a short rest, the country's currency and meal shares`() {
        val c = loggedIn("perf.sales.0001")
        val de = trip(c, 30, mapOf("country" to "DE", "destination" to "München", "breakfasts" to 1))
        assertEquals("EUR", de["currency"].asString())
        assertAmount("65.33", de, "dietAmount") // one day + a third of 49
        assertAmount("7.35", de, "mealDeduction") // breakfast 15 %
        assertEquals(51242, c.post("/api/trips", body(30, mapOf("country" to "DE", "destination" to "Berlin",
            "transport" to "PRIVATE_CAR", "vehicle" to "CAR_GT_900", "kilometres" to 600)))["errorNumber"])
    }

    @Test
    fun `what each purpose needs`() {
        val c = loggedIn("perf.sales.0001")
        assertEquals(51237, c.post("/api/trips", body(8, mapOf("purpose" to "CLIENT_VISIT")))["errorNumber"])
        assertEquals(51238, c.post("/api/trips", body(8, mapOf("purpose" to "TRADE_FAIR")))["errorNumber"])
        assertEquals(51239, c.post("/api/trips", body(8, mapOf("purpose" to "PROJECT_SITE")))["errorNumber"])
        assertEquals(51243, c.post("/api/trips", body(8, mapOf("lunches" to 3)))["errorNumber"])
        assertEquals(51241, c.post("/api/trips", body(0))["errorNumber"])
        val visit = trip(c, 8, mapOf("purpose" to "CLIENT_VISIT", "clientId" to client(c)))
        assertTrue(Regex("DEL/\\d{4}/\\d{4,}").matches(visit["number"].asString()))
        assertEquals("PLANNED", visit["status"].asString())
        val fair = trip(c, 50, mapOf("purpose" to "TRADE_FAIR", "eventName" to "Targi Budma"))
        assertEquals("Targi Budma", fair["eventName"].asString())
    }

    @Test
    fun `expenses, the hotel limit and the advance`() {
        val c = loggedIn("perf.sales.0001")
        val t = trip(c, 30, mapOf("advance" to 500))
        val id = t["id"].asLong()
        val day = "2026-10-05"
        fun save(items: List<Map<String, Any?>>, rv: String) = c.put("/api/trips/$id/expenses", mapOf("items" to items, "rowVersion" to rv))
        assertEquals(51246, save(listOf(mapOf("category" to "HOTEL", "description" to "Hotel", "spentOn" to day, "amount" to 300)), t["rowVersion"].asString())["errorNumber"])
        val saved = save(listOf(
            mapOf("category" to "HOTEL", "description" to "Hotel Łódź", "spentOn" to day, "amount" to 1000, "nights" to 1),
            mapOf("category" to "TICKET", "description" to "PKP", "spentOn" to day, "amount" to 89.90),
        ), t["rowVersion"].asString()).body!!
        assertAmount("1089.90", saved, "expensesAmount")
        assertTrue(saved["hotelOverLimit"].asBoolean(), "900 zł a night is the domestic limit")
        assertAmount((amount(saved, "total") - BigDecimal("500")).toPlainString(), saved, "toPay")
        assertEquals(2, c.get("/api/trips/$id/expenses").body!!.list().size)
    }

    @Test
    fun `the way of a settlement - submitted after the trip, approved by somebody else, paid`() {
        val sales = loggedIn("perf.sales.0001")
        val future = trip(sales, 8, from = Instant.now().plus(5, ChronoUnit.DAYS))
        assertEquals(51929, sales.post("/api/trips/${future["id"].asLong()}/status", mapOf("action" to "SUBMIT", "rowVersion" to future["rowVersion"].asString()))["errorNumber"])
        val cancelled = sales.post("/api/trips/${future["id"].asLong()}/status", mapOf("action" to "CANCEL", "rowVersion" to future["rowVersion"].asString())).body!!
        assertEquals("CANCELLED", cancelled["status"].asString())

        val t = trip(sales, 10)
        val id = t["id"].asLong()
        fun step(c: ApiClient, action: String, rv: String, note: String? = null) =
            c.post("/api/trips/$id/status", mapOf("action" to action, "note" to note, "rowVersion" to rv))
        val submitted = step(sales, "SUBMIT", t["rowVersion"].asString()).body!!
        assertEquals(51931, step(sales, "APPROVE", submitted["rowVersion"].asString())["errorNumber"], "a salesperson does not approve")
        assertEquals(404, loggedIn("perf.sales.0002").get("/api/trips/$id").status)
        val manager = loggedIn("perf.manager.0001")
        val travellerId = t["travellerUserId"].asInt()
        assertTrue(manager.get("/api/trips?scope=TO_APPROVE&travellerUserId=$travellerId&size=200").body!!["items"].list().any { it["id"].asLong() == id })
        assertEquals(51247, step(manager, "RETURN", submitted["rowVersion"].asString())["errorNumber"])
        val returned = step(manager, "RETURN", submitted["rowVersion"].asString(), "Dołącz bilet").body!!
        assertEquals("RETURNED", returned["status"].asString())
        val fixed = sales.put("/api/trips/$id", body(10, mapOf("description" to "Z biletem", "rowVersion" to returned["rowVersion"].asString()))).body!!
        val again = step(sales, "SUBMIT", fixed["rowVersion"].asString()).body!!
        val approved = step(manager, "APPROVE", again["rowVersion"].asString()).body!!
        assertEquals("APPROVED", approved["status"].asString())
        assertEquals(51928, sales.put("/api/trips/$id", body(10, mapOf("rowVersion" to approved["rowVersion"].asString())))["errorNumber"])
        assertEquals("PAID", step(manager, "PAY", approved["rowVersion"].asString()).body!!["status"].asString())

        val own = trip(manager, 10)
        val ownSubmitted = manager.post("/api/trips/${own["id"].asLong()}/status", mapOf("action" to "SUBMIT", "rowVersion" to own["rowVersion"].asString())).body!!
        assertEquals(51930, manager.post("/api/trips/${own["id"].asLong()}/status", mapOf("action" to "APPROVE", "rowVersion" to ownSubmitted["rowVersion"].asString()))["errorNumber"])
    }

    @Test
    fun `rates and the seeded trips`() {
        val manager = loggedIn("perf.manager.0001")
        val rates = manager.get("/api/trips/rates").body!!.list()
        assertTrue(rates.any { it["code"].asString() == "PL" && BigDecimal(it["amount"].asString()).compareTo(BigDecimal("45")) == 0 }, rates.toString())
        assertTrue(rates.any { it["code"].asString() == "CAR_GT_900" }, rates.toString())
        val all = manager.get("/api/trips?scope=ALL&size=200").body!!["items"].list()
        assertTrue(all.size > 20, "trips: ${all.size}")
        assertTrue(all.map { it["purpose"].asString() }.toSet().containsAll(listOf("CLIENT_VISIT", "TRADE_FAIR")), all.map { it["purpose"].asString() }.toSet().toString())
        assertTrue(manager.get("/api/trips?scope=ALL&status=PAID").body!!["items"].list().isNotEmpty(), "paid")
        // Numbers stay unique past 9 999 a year: the seed numbers as app.trip_create does.
        assertEquals(scalar<Int>("SELECT COUNT(*) FROM crm.trips"), scalar<Int>("SELECT COUNT(DISTINCT number) FROM crm.trips"))
    }
}
