package crm

import crm.desk.charts.DeskCharts
import crm.support.IntegrationTest
import crm.support.list
import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The desk charts (ADR-0011): the numbers agree with each other and with the lists. */
class DeskChartHttpTest : IntegrationTest() {

    @Test
    fun `median and nearest-rank p90`() {
        assertNull(DeskCharts.median(emptyList()))
        assertEquals(2.0, DeskCharts.median(listOf(3.0, 1.0, 2.0)))
        assertEquals(2.5, DeskCharts.median(listOf(4.0, 1.0, 2.0, 3.0)))
        assertEquals(9.0, DeskCharts.percentile((1..10).map { it.toDouble() }, 0.9))
        assertEquals(5.0, DeskCharts.percentile(listOf(5.0), 0.9))
    }

    @Test
    fun `the numbers agree - heatmap, flow, queue and counters`() {
        val c = loggedIn("tomasz.wojcik")
        // One ticket reported, taken and resolved now, in a category of its own for this test.
        val ticket = c.post(
            "/api/desk/tickets",
            mapOf(
                "title" to "Test wykresy", "description" to "Opis", "categoryKey" to "legalization",
                "subcategoryKey" to "legalization.pesel", "priority" to "HIGH", "reportedAt" to Instant.now().toString(),
                "requesterIncognito" to true,
            ),
        ).body!!
        c.post("/api/desk/tickets/${ticket["id"].asLong()}/take", null)
        c.post("/api/desk/tickets/${ticket["id"].asLong()}/resolve", null)

        for (range in listOf("DAYS_7", "DAYS_30", "WEEKS_12")) {
            val data = c.get("/api/desk/charts?range=$range").body!!
            val figures = data["figures"]
            val flow = data["flow"].list()
            assertEquals(if (range == "DAYS_7") 7 else if (range == "DAYS_30") 30 else 12, flow.size)
            assertEquals(figures["reported"].asInt(), flow.sumOf { it["reported"].asInt() })
            assertEquals(figures["resolved"].asInt(), flow.sumOf { it["resolved"].asInt() })
            assertEquals(figures["openNow"].asInt(), flow.last()["openAtEnd"].asInt())
            assertEquals(figures["reported"].asInt(), data["heat"].list().sumOf { row -> row.list().sumOf { it.asInt() } })
            assertEquals(figures["reported"].asInt(), data["byCategory"].list().sumOf { b -> b["values"].list().sumOf { it.asInt() } })
            val queue = data["queue"].list()
            assertEquals(figures["openNow"].asInt(), queue.sumOf { b -> b["values"].list().sumOf { it.asInt() } })
            assertEquals(figures["overdueNow"].asInt(), queue.sumOf { it["values"][2].asInt() })
            assertEquals(figures["resolved"].asInt(), data["agents"].list().sumOf { b -> b["values"].list().sumOf { it.asInt() } })
        }

        val counters = c.get("/api/desk/tickets/counters").body!!
        val all = c.get("/api/desk/charts?range=DAYS_30").body!!["figures"]
        assertEquals(counters["overdue"].asInt(), all["overdueNow"].asInt())
        assertEquals(counters["dueSoon"].asInt(), all["dueSoonNow"].asInt())

        val legalization = c.get("/api/desk/charts?range=DAYS_7&categoryKey=legalization").body!!
        assertTrue(legalization["bySubcategory"].asBoolean())
        assertTrue(legalization["byCategory"].list().any { it["key"].asString() == "legalization.pesel" })
        val high = legalization["sla"].list().first { it["priority"].asString() == "HIGH" }
        // The seed's histories share the category, so only what this ticket guarantees: it counts, with a median.
        assertTrue(high["count"].asInt() >= 1 && !high["median"].isNull && high["medianMinutes"].asLong() >= 0)
        assertEquals(400, c.get("/api/desk/charts?range=YEARS").status)
    }
}
