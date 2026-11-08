package crm.support

import tools.jackson.databind.JsonNode
import tools.jackson.databind.json.JsonMapper
import java.net.CookieManager
import java.net.HttpCookie
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse

data class ApiResponse(val status: Int, val body: JsonNode?)

/**
 * A real HTTP client with its own cookie jar (session + XSRF-TOKEN), like a browser or k6 VU.
 */
class ApiClient(private val baseUrl: String) {
    private val mapper = JsonMapper.builder().build()
    private val cookies = CookieManager()
    private val http = HttpClient.newBuilder().cookieHandler(cookies).build()

    private fun xsrf(): String? =
        cookies.cookieStore.cookies.firstOrNull { it.name == "XSRF-TOKEN" }?.value

    fun hasCookie(name: String): Boolean = cookies.cookieStore.cookies.any { it.name == name }

    fun dropCookie(name: String) {
        cookies.cookieStore.cookies.filter { it.name == name }.forEach { c: HttpCookie ->
            cookies.cookieStore.remove(URI(baseUrl), c)
        }
    }

    fun csrf(): ApiResponse = send("GET", "/api/auth/csrf", null, withCsrf = false)

    fun login(login: String, password: String): ApiResponse {
        csrf()
        return post("/api/auth/login", mapOf("login" to login, "password" to password))
    }

    fun get(path: String) = send("GET", path, null)

    fun post(path: String, body: Any?, withCsrf: Boolean = true) = send("POST", path, body, withCsrf)

    fun put(path: String, body: Any?) = send("PUT", path, body)

    fun delete(path: String) = send("DELETE", path, null)

    private fun send(method: String, path: String, body: Any?, withCsrf: Boolean = true): ApiResponse {
        val builder = HttpRequest.newBuilder(URI("$baseUrl$path"))
            .header("Content-Type", "application/json")
            .method(
                method,
                if (body == null) HttpRequest.BodyPublishers.noBody()
                else HttpRequest.BodyPublishers.ofString(mapper.writeValueAsString(body)),
            )
        if (withCsrf) xsrf()?.let { builder.header("X-XSRF-TOKEN", it) }
        val response = http.send(builder.build(), HttpResponse.BodyHandlers.ofString())
        val json = response.body().takeIf { it.isNotBlank() }?.let { runCatching { mapper.readTree(it) }.getOrNull() }
        return ApiResponse(response.statusCode(), json)
    }
}

/** Elements of a JSON array as a Kotlin list. */
fun JsonNode.list(): List<JsonNode> = (0 until size()).map { this[it] }
