package crm

import crm.support.ApiClient
import crm.support.IntegrationTest
import crm.support.Part
import crm.support.list
import org.apache.poi.xssf.usermodel.XSSFWorkbook
import org.junit.jupiter.api.Test
import tools.jackson.databind.JsonNode
import tools.jackson.databind.json.JsonMapper
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Report data of tickets and the desk reports with their exports (ADR-0010). */
class DeskReportHttpTest : IntegrationTest() {

    private val json = JsonMapper.builder().build()

    private fun report(c: ApiClient, sub: String, category: String, fields: Map<String, String?>, title: String = "Test raport ${System.nanoTime()}") =
        c.post(
            "/api/desk/tickets",
            mapOf(
                "title" to title, "description" to "Dane do raportu", "categoryKey" to category,
                "subcategoryKey" to sub, "priority" to "MEDIUM", "reportedAt" to Instant.now().toString(),
                "requesterIncognito" to true, "fields" to fields,
            ),
        )

    private fun fields(c: ApiClient, ticket: JsonNode) =
        c.get("/api/desk/tickets/${ticket["id"].asLong()}/fields").body!!.list().associate { it["key"].asString() to it["value"].asString() }

    private operator fun crm.support.ApiResponse.get(key: String): Int? = body?.get(key)?.takeUnless { it.isNull }?.asInt()

    private val onboarding = mapOf("first-name" to "Jan", "last-name" to "Kowalski", "department" to "it")

    @Test
    fun `values are checked and stored in their normal form`() {
        val c = loggedIn("anna.nowak")
        val payment = report(
            c, "finance.payments", "finance",
            mapOf("amount" to "1 234,5", "currency" to "eur", "due-date" to "2026-12-01", "bank-account" to "61 1090 1014 0000 0712 1981 2874"),
        )
        assertEquals(201, payment.status, payment.body.toString())
        assertEquals(
            mapOf("amount" to "1234.50", "currency" to "EUR", "due-date" to "2026-12-01", "bank-account" to "PL61109010140000071219812874"),
            fields(c, payment.body!!),
        )
        val stream = c.get("/api/desk/tickets/${payment.body!!["id"].asLong()}/events").body!!.list()
        assertEquals("1234.50", json.readTree(stream[0]["data"].asString())["fields"]["amount"].asString())

        val campaign = report(c, "marketing.budget", "marketing", mapOf("channels" to "tiktok, Facebook", "amount" to "500", "headcount" to "3"))
        assertEquals(201, campaign.status, campaign.body.toString())
        assertEquals("Facebook, TikTok", fields(c, campaign.body!!)["channels"], "multi-choice in the list's order")

        val person = report(c, "hr-poland.pl.onboarding", "hr-poland", onboarding + mapOf("identity-document" to "Dowód osobisty", "identity-number" to "abc 123456"))
        assertEquals(201, person.status, person.body.toString())
        assertEquals("ABC123456", fields(c, person.body!!)["identity-number"])
        assertEquals("IT", fields(c, person.body!!)["department"])
    }

    @Test
    fun `refusals of report data`() {
        val c = loggedIn("anna.nowak")
        fun refused(sub: String, category: String, values: Map<String, String?>) = report(c, sub, category, values)["errorNumber"]
        assertEquals(51131, refused("hr-poland.pl.onboarding", "hr-poland", mapOf("first-name" to "Jan")))
        assertEquals(51130, refused("finance.payments", "finance", mapOf("limosa-number" to "L1")))
        assertEquals(51133, refused("finance.payments", "finance", mapOf("due-date" to "1.12.2026")))
        assertEquals(51135, refused("finance.payments", "finance", mapOf("amount" to "12,345")))
        assertEquals(51136, refused("finance.payments", "finance", mapOf("bank-account" to "PL61109010140000071219812875")))
        assertEquals(51139, refused("finance.payments", "finance", mapOf("currency" to "BTC")))
        assertEquals(51137, refused("marketing.budget", "marketing", mapOf("channels" to "Facebook", "amount" to "1", "headcount" to "0")))
        assertEquals(51138, refused("marketing.budget", "marketing", mapOf("channels" to "Facebook, Myspace", "amount" to "1")))
        assertEquals(51140, refused("marketing.budget", "marketing", mapOf("channels" to "Facebook", "amount" to "1", "related-ticket" to "HAL-123")))
        assertEquals(51134, refused("hr-poland.pl.onboarding", "hr-poland", onboarding + ("email" to "jan@")))
        assertEquals(51141, refused("hr-poland.pl.onboarding", "hr-poland", onboarding + ("identity-number" to "123")))
        assertEquals(51142, refused("hr-poland.pl.onboarding", "hr-poland", onboarding + mapOf("identity-document" to "Brak dokumentów", "identity-number" to "1")))
        assertEquals(51143, refused("hr-poland.pl.onboarding", "hr-poland", onboarding + ("identity-document" to "PESEL")))
        assertEquals(51144, refused("hr-poland.pl.onboarding", "hr-poland", onboarding + mapOf("identity-document" to "PESEL", "identity-number" to "44051401358")))
        assertEquals(201, report(c, "hr-poland.pl.onboarding", "hr-poland", onboarding + mapOf("identity-document" to "PESEL", "identity-number" to "44051401359")).status)
    }

    @Test
    fun `update lists only the changes, nothing changed stores nothing, required stays`() {
        val c = loggedIn("piotr.kowalski")
        val ticket = report(c, "finance.payments", "finance", mapOf("amount" to "100")).body!!
        val t = "/api/desk/tickets/${ticket["id"].asLong()}"
        val updated = c.put("$t/fields", mapOf("values" to mapOf("amount" to "100.00", "contractor" to "ACME", "currency" to "PLN")))
        assertEquals(200, updated.status, updated.body.toString())
        val event = c.get("$t/events").body!!.list().last()
        assertEquals("TicketFieldsUpdated", event["type"].asString())
        val changes = json.readTree(event["data"].asString())["changes"].list()
        assertEquals(listOf("contractor", "currency"), changes.map { it["key"].asString() }, "the amount did not change")
        assertTrue(changes[0]["from"].isNull)

        val same = c.put("$t/fields", mapOf("values" to mapOf("amount" to "100", "contractor" to "ACME", "currency" to "PLN"))).body!!
        assertEquals(updated.body!!["version"].asInt(), same["version"].asInt())

        val cleared = c.put("$t/fields", mapOf("values" to mapOf("amount" to "100"))).body!!
        assertEquals(mapOf("amount" to "100.00"), fields(c, cleared))

        val noFields = report(c, "finance.feedback", "finance", emptyMap()).body!!
        assertEquals(51146, c.put("/api/desk/tickets/${noFields["id"].asLong()}/fields", mapOf("values" to mapOf("x" to "1")))["errorNumber"])
        val person = report(c, "hr-poland.pl.onboarding", "hr-poland", onboarding).body!!
        assertEquals(51131, c.put("/api/desk/tickets/${person["id"].asLong()}/fields", mapOf("values" to mapOf("first-name" to "Jan")))["errorNumber"])
    }

    @Test
    fun `campaigns ordered for a recruitment ticket are linked by its number`() {
        val c = loggedIn("anna.nowak")
        val recruitment = report(c, "recruitment.internal", "recruitment", mapOf("position" to "Spawacz")).body!!
        val campaign = report(
            c, "marketing.budget", "marketing",
            mapOf("channels" to "Facebook", "amount" to "2000", "related-ticket" to recruitment["number"].asString().lowercase()),
        ).body!!
        val linked = c.get("/api/desk/tickets/${recruitment["id"].asLong()}/linked").body!!.list()
        assertEquals(listOf(campaign["id"].asLong()), linked.map { it["id"].asLong() })
    }

    @Test
    fun `category report - only fields with a value become columns, exports carry the same table`() {
        val c = loggedIn("anna.nowak")
        val title = "=HYPERLINK(\"x\") raport ${System.nanoTime()}"
        report(c, "finance.payments", "finance", mapOf("amount" to "1234.56", "contractor" to "ACME"), title)
        val today = LocalDate.now(ZoneId.of("Europe/Warsaw"))
        val q = "from=$today&to=$today"
        val table = c.get("/api/desk/reports/categories/finanse?$q").body!!
        val keys = table["columns"].list().map { it["key"].asString() }
        assertTrue("field:amount" in keys && "field:contractor" in keys)
        assertTrue("field:limosa-number" !in keys && "market" !in keys)
        val row = table["rows"].list().first { it[keys.indexOf("title")].asString() == title }
        assertEquals("1234.56", row[keys.indexOf("field:amount")].asString())
        assertEquals("Zgłoszenie do Finansów", table["title"].asString())
        val english = c.get("/api/desk/reports/categories/finanse?$q&lang=en").body!!
        assertEquals("Number", english["columns"][0]["label"].asString())
        assertTrue(english["title"].asString() != table["title"].asString(), "catalog names in English")

        val csv = c.download("/api/desk/reports/categories/finanse/export.csv?$q")
        assertEquals(200, csv.status)
        assertTrue(csv.header("Content-Disposition")!!.contains("raport-finanse-$today.csv"))
        val text = String(csv.bytes, Charsets.UTF_8)
        assertTrue(text.startsWith("﻿Numer;"))
        assertTrue(text.contains("\"'=HYPERLINK(\"\"x\"\")"), "a formula is neutralised")
        assertTrue(text.contains("1234,56"), "decimal comma")

        val xlsx = c.download("/api/desk/reports/categories/finanse/export.xlsx?$q")
        XSSFWorkbook(xlsx.bytes.inputStream()).use { book ->
            val sheet = book.getSheetAt(0)
            assertEquals("Numer", sheet.getRow(0).getCell(0).stringCellValue)
            assertEquals(table["rows"].list().size, sheet.lastRowNum)
            val amountColumn = keys.indexOf("field:amount")
            val amounts = (1..sheet.lastRowNum).mapNotNull { sheet.getRow(it).getCell(amountColumn) }.map { it.numericCellValue }
            assertTrue(1234.56 in amounts)
        }
        val pdf = c.download("/api/desk/reports/categories/finanse/export.pdf?$q")
        assertEquals("%PDF", String(pdf.bytes.copyOfRange(0, 4)))
        assertEquals(404, c.get("/api/desk/reports/categories/nope?$q").status)
        assertEquals(400, c.get("/api/desk/reports/categories/finanse?from=$today&to=${today.minusDays(1)}").status)
    }

    @Test
    fun `agents report counts taking and resolving from the events`() {
        val c = loggedIn("joanna.wozniak")
        val before = agentRow(c)
        val ticket = report(c, "finance.feedback", "finance", emptyMap()).body!!
        c.post("/api/desk/tickets/${ticket["id"].asLong()}/take", null)
        c.post("/api/desk/tickets/${ticket["id"].asLong()}/resolve", null)
        val after = agentRow(c)
        assertEquals(before.week.first + 1, after.week.first, "taken this week")
        assertEquals(before.week.second + 1, after.week.second, "resolved this week")
        val table = c.get("/api/desk/reports/agents").body!!
        assertEquals("Razem", table["totals"][0].asString())
        assertEquals(200, c.download("/api/desk/reports/agents/export.xlsx").status)
        assertEquals(200, c.get("/api/desk/reports/agents?previous=true").status)
    }

    private data class AgentCounts(val week: Pair<Long, Long>)

    private fun agentRow(c: ApiClient): AgentCounts {
        val table = c.get("/api/desk/reports/agents").body!!
        val row = table["rows"].list().firstOrNull { it[0].asString() == "Joanna Woźniak" }
        return AgentCounts(if (row == null) 0L to 0L else row[1].asString().toLong() to row[2].asString().toLong())
    }

    @Test
    fun `the public form sends report data as a JSON field`() {
        val anonymous = client()
        anonymous.csrf()
        val parts = mapOf(
            "title" to "Test formularz z danymi", "description" to "Nowy pracownik", "categoryKey" to "hr-poland",
            "subcategoryKey" to "hr-poland.pl.onboarding", "priority" to "LOW", "requesterIncognito" to "true",
            "fields" to json.writeValueAsString(onboarding),
        ).map { (k, v) -> Part(k, v.toByteArray()) }
        val sent = anonymous.multipart("/api/public/desk/tickets", parts)
        assertEquals(201, sent.status, sent.body.toString())
        val ticket = loggedIn("anna.nowak").get("/api/desk/tickets/by-number/${sent.body!!["number"].asString()}").body!!
        assertEquals("Kowalski", fields(loggedIn("anna.nowak"), ticket)["last-name"])
    }
}
