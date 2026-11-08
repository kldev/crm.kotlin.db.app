package crm

import crm.support.ApiClient
import crm.support.IntegrationTest
import crm.support.list
import org.junit.jupiter.api.Test
import org.openpdf.text.pdf.PdfReader
import org.openpdf.text.pdf.parser.PdfTextExtractor
import tools.jackson.databind.JsonNode
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Offers from templates, their rules and the PDF (ADR-0013). */
class OfferHttpTest : IntegrationTest() {

    private operator fun crm.support.ApiResponse.get(key: String): Int? = body?.get(key)?.takeUnless { it.isNull }?.asInt()

    private fun ownClient(c: ApiClient): Long =
        c.post("/api/clients", mapOf("name" to "Test Ofertowy ${System.nanoTime()}", "city" to "Poznań", "status" to "ACTIVE"))
            .body!!["id"].asLong()

    private fun create(c: ApiClient, clientId: Long, template: String = "IT"): JsonNode {
        val response = c.post("/api/offers", mapOf("clientId" to clientId, "templateKey" to template))
        assertEquals(201, response.status, response.body.toString())
        return response.body!!
    }

    private fun pdfText(c: ApiClient, id: Long, lang: String = "pl"): String {
        val pdf = c.download("/api/offers/$id/pdf?lang=$lang")
        assertEquals(200, pdf.status)
        assertEquals("%PDF", String(pdf.bytes.copyOfRange(0, 4)))
        val reader = PdfReader(pdf.bytes)
        return (1..reader.numberOfPages).joinToString("\n") { PdfTextExtractor(reader).getTextFromPage(it) }
    }

    @Test
    fun `three templates, a new offer copies its texts and lines, totals are computed`() {
        val c = loggedIn("anna.nowak")
        val templates = c.get("/api/offers/templates").body!!.list()
        assertEquals(listOf("Sales Budownictwo", "Sales IT", "Sales Outsourcing"), templates.map { it["namePl"].asString() })

        val offer = create(c, ownClient(c), "CONSTRUCTION")
        assertEquals("DRAFT", offer["status"].asString())
        assertTrue(Regex("OF/\\d{4}/\\d{4,}").matches(offer["number"].asString()))
        assertEquals("Oferta na prace budowlane", offer["title"].asString())
        assertEquals(LocalDate.now().plusDays(30).toString().take(7), offer["validUntil"].asString().take(7))
        val items = c.get("/api/offers/${offer["id"].asLong()}/items").body!!.list()
        assertEquals(4, items.size)
        val net = items.sumOf { BigDecimal(it["quantity"].asString()).multiply(BigDecimal(it["unitPrice"].asString())).setScale(2, RoundingMode.HALF_UP) }
        assertEquals(0, net.compareTo(BigDecimal(offer["totalNet"].asString())))
        val vat = items.sumOf { BigDecimal(it["vat"].asString()) }
        assertEquals(0, vat.compareTo(BigDecimal(offer["totalVat"].asString())))
        assertEquals(0, net.add(vat).compareTo(BigDecimal(offer["totalGross"].asString())))
    }

    @Test
    fun `a salesperson works only on offers of own clients`() {
        val other = loggedIn("perf.sales.0002")
        val foreign = create(other, ownClient(other))
        val sales = loggedIn("perf.sales.0001")
        assertEquals(404, sales.get("/api/offers/${foreign["id"].asLong()}").status)
        assertEquals(51401, sales.post("/api/offers", mapOf("clientId" to foreign["clientId"].asLong(), "templateKey" to "IT"))["errorNumber"])
        assertTrue(sales.get("/api/offers?size=200").body!!["items"].list().none { it["id"].asLong() == foreign["id"].asLong() })
        assertEquals(200, loggedIn("perf.manager.0001").get("/api/offers/${foreign["id"].asLong()}").status)
    }

    @Test
    fun `drafts are edited with their lines, sent offers are not, transitions follow the rules`() {
        val c = loggedIn("anna.nowak")
        val offer = create(c, ownClient(c))
        val id = offer["id"].asLong()
        fun body(rowVersion: String, items: List<Map<String, Any?>>, validUntil: LocalDate = LocalDate.now().plusDays(10)) = mapOf(
            "title" to "Wdrożenie CRM", "intro" to "Wstęp", "terms" to "Płatność 14 dni", "currency" to "EUR",
            "validUntil" to validUntil.toString(), "items" to items, "rowVersion" to rowVersion,
        )
        val line = mapOf("description" to "Konfiguracja", "unit" to "h", "quantity" to 10, "unitPrice" to 199.99, "vatRate" to 23)
        assertEquals(51173, c.put("/api/offers/$id", body(offer["rowVersion"].asString(), listOf(line + ("vatRate" to 7))))["errorNumber"])
        assertEquals(51172, c.put("/api/offers/$id", body(offer["rowVersion"].asString(), listOf(line), LocalDate.now().minusDays(1)))["errorNumber"])
        val updated = c.put("/api/offers/$id", body(offer["rowVersion"].asString(), listOf(line))).body!!
        assertEquals("EUR", updated["currency"].asString())
        assertEquals(0, BigDecimal("2459.88").compareTo(BigDecimal(updated["totalGross"].asString())), updated.toString())
        assertEquals(409, c.put("/api/offers/$id", body(offer["rowVersion"].asString(), listOf(line))).status, "stale rowVersion")

        val empty = create(c, offer["clientId"].asLong())
        val emptied = c.put("/api/offers/${empty["id"].asLong()}", body(empty["rowVersion"].asString(), emptyList())).body!!
        assertEquals(51176, c.post("/api/offers/${empty["id"].asLong()}/status", mapOf("status" to "SENT", "rowVersion" to emptied["rowVersion"].asString()))["errorNumber"])

        assertEquals(51907, c.post("/api/offers/$id/status", mapOf("status" to "ACCEPTED", "rowVersion" to updated["rowVersion"].asString()))["errorNumber"])
        val sent = c.post("/api/offers/$id/status", mapOf("status" to "SENT", "rowVersion" to updated["rowVersion"].asString())).body!!
        assertEquals("SENT", sent["status"].asString())
        assertEquals(51906, c.put("/api/offers/$id", body(sent["rowVersion"].asString(), listOf(line)))["errorNumber"])
        assertEquals(51906, c.delete("/api/offers/$id?rowVersion=${sent["rowVersion"].asString()}")["errorNumber"])
        val accepted = c.post("/api/offers/$id/status", mapOf("status" to "ACCEPTED", "rowVersion" to sent["rowVersion"].asString())).body!!
        assertEquals("ACCEPTED", accepted["status"].asString())
        assertEquals(51907, c.post("/api/offers/$id/status", mapOf("status" to "DRAFT", "rowVersion" to accepted["rowVersion"].asString()))["errorNumber"])

        assertEquals(204, c.delete("/api/offers/${empty["id"].asLong()}?rowVersion=${emptied["rowVersion"].asString()}").status)
        assertEquals(404, c.get("/api/offers/${empty["id"].asLong()}").status)
    }

    @Test
    fun `the PDF closes with the salesperson's contact, or the company's for others`() {
        val sales = loggedIn("anna.nowak")
        sales.put("/api/auth/me/contact", mapOf("jobTitle" to "Doradca handlowy", "phone" to "+48 600 100 101", "email" to "anna.nowak@company.io"))
        val offer = create(sales, ownClient(sales), "OUTSOURCING")
        val text = pdfText(sales, offer["id"].asLong())
        assertTrue("Halycon Staff" in text, text.take(300)) // the template's company signs (ADR-0016)
        assertTrue(offer["number"].asString() in text)
        assertTrue("Twój opiekun oferty" in text && "Anna Nowak" in text && "+48 600 100 101" in text, text)
        assertTrue("Spawacz MIG/MAG" in text)
        assertTrue("Your contact for this offer" in pdfText(sales, offer["id"].asLong(), "en"))

        val manager = loggedIn("perf.manager.0001")
        val managerOffer = create(manager, ownClient(manager), "CONSTRUCTION")
        val managerText = pdfText(manager, managerOffer["id"].asLong())
        assertTrue("Twój opiekun oferty" !in managerText && "+48 22 100 20 40" in managerText, managerText)
    }

    @Test
    fun `contacts - own for everybody, anyone's for admins, checked`() {
        val sales = loggedIn("perf.sales.0001")
        assertEquals(51177, sales.put("/api/auth/me/contact", mapOf("phone" to "abc"))["errorNumber"])
        assertEquals(51177, sales.put("/api/auth/me/contact", mapOf("email" to "no-at"))["errorNumber"])
        val mine = sales.put("/api/auth/me/contact", mapOf("jobTitle" to "Handlowiec", "phone" to "+48 501 000 001", "email" to " Sales@Example.com ")).body!!
        assertEquals("sales@example.com", mine["email"].asString())
        val me = sales.get("/api/auth/me").body!!["id"].asInt()
        assertEquals(403, sales.put("/api/users/${me + 1}/contact", mapOf("phone" to "123456")).status)
        val admin = loggedIn(ADMIN_LOGIN, ADMIN_PASSWORD)
        assertEquals("+48 600 000 000", admin.put("/api/users/$me/contact", mapOf("phone" to "+48 600 000 000")).body!!["phone"].asString())
        assertEquals("+48 600 000 000", sales.get("/api/auth/me/contact").body!!["phone"].asString())
    }
}
