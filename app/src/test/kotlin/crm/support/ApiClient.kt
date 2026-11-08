package crm.support

import tools.jackson.databind.JsonNode
import tools.jackson.databind.json.JsonMapper
import java.net.CookieManager
import java.net.HttpCookie
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse

data class ApiResponse(val status: Int, val body: JsonNode?, val headers: Map<String, List<String>> = emptyMap(), val bytes: ByteArray = ByteArray(0)) {
    fun header(name: String): String? = headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value?.firstOrNull()
}

/** A part of a multipart request: a form field (`fileName` null) or a file. */
data class Part(val name: String, val content: ByteArray, val fileName: String? = null, val contentType: String = "application/octet-stream")

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

    /** multipart/form-data POST (with the CSRF header), like a browser's FormData. */
    fun multipart(path: String, parts: List<Part>): ApiResponse {
        val boundary = "----crmtest${System.nanoTime()}"
        val body = java.io.ByteArrayOutputStream()
        for (part in parts) {
            body.write("--$boundary\r\n".toByteArray())
            val file = part.fileName?.let { "; filename=\"$it\"" } ?: ""
            body.write("Content-Disposition: form-data; name=\"${part.name}\"$file\r\n".toByteArray())
            if (part.fileName != null) body.write("Content-Type: ${part.contentType}\r\n".toByteArray())
            body.write("\r\n".toByteArray())
            body.write(part.content)
            body.write("\r\n".toByteArray())
        }
        body.write("--$boundary--\r\n".toByteArray())
        val builder = HttpRequest.newBuilder(URI("$baseUrl$path"))
            .header("Content-Type", "multipart/form-data; boundary=$boundary")
            .POST(HttpRequest.BodyPublishers.ofByteArray(body.toByteArray()))
        xsrf()?.let { builder.header("X-XSRF-TOKEN", it) }
        return toApiResponse(http.send(builder.build(), HttpResponse.BodyHandlers.ofByteArray()))
    }

    /** GET returning the raw bytes and headers (downloads). */
    fun download(path: String): ApiResponse {
        val request = HttpRequest.newBuilder(URI("$baseUrl$path")).GET().build()
        return toApiResponse(http.send(request, HttpResponse.BodyHandlers.ofByteArray()))
    }

    private fun toApiResponse(response: HttpResponse<ByteArray>): ApiResponse {
        val bytes = response.body()
        val isJson = response.headers().firstValue("Content-Type").orElse("").contains("json")
        val json = if (isJson && bytes.isNotEmpty()) runCatching { mapper.readTree(bytes) }.getOrNull() else null
        return ApiResponse(response.statusCode(), json, response.headers().map(), bytes)
    }

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
