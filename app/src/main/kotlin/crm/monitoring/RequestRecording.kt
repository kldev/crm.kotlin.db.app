package crm.monitoring

import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.slf4j.MDC
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication
import org.springframework.boot.web.servlet.FilterRegistrationBean
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.core.Ordered
import org.springframework.security.core.context.SecurityContext
import org.springframework.security.web.context.HttpSessionSecurityContextRepository
import org.springframework.web.filter.OncePerRequestFilter
import java.time.Instant
import java.util.UUID

/**
 * Records every HTTP answer (ADR-0012) - success or error - first in the chain, so it sees the status the client got
 * (after Spring Security and the exception handlers). The path is kept without the query string. A trace id is put in
 * the MDC for the log entries written during the request. Probes and static files are skipped.
 */
class RequestRecordingFilter(
    private val queue: MonitoringQueue,
    private val properties: MonitoringProperties,
) : OncePerRequestFilter() {

    override fun shouldNotFilter(request: HttpServletRequest): Boolean {
        val path = request.requestURI
        return !properties.enabled || properties.ignoredPaths.any { path.startsWith(it) }
    }

    override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {
        val started = System.nanoTime()
        val traceId = UUID.randomUUID().toString().replace("-", "").take(16)
        MDC.put(TRACE_ID, traceId)
        MDC.put(REQUEST_PATH, request.requestURI)
        var status: Int? = null
        try {
            chain.doFilter(request, response)
        } catch (error: Throwable) {
            // Not handled by Spring: the container answers 500.
            status = 500
            throw error
        } finally {
            queue.add(
                RecordedRequest(
                    at = Instant.now(),
                    method = request.method,
                    path = request.requestURI,
                    status = status ?: response.status,
                    elapsedMs = (System.nanoTime() - started) / 1_000_000,
                    user = userOf(request),
                    traceId = traceId,
                ),
            )
            MDC.remove(TRACE_ID)
            MDC.remove(REQUEST_PATH)
        }
    }

    /** The signed-in user from the session (Spring Security has cleared its holder by now). */
    private fun userOf(request: HttpServletRequest): String? {
        val context = request.getSession(false)
            ?.getAttribute(HttpSessionSecurityContextRepository.SPRING_SECURITY_CONTEXT_KEY) as? SecurityContext
        return context?.authentication?.name
    }

    companion object {
        const val TRACE_ID = "traceId"
        const val REQUEST_PATH = "requestPath"
    }
}

@Configuration
@ConditionalOnWebApplication
class RequestRecordingConfig {
    @Bean
    fun requestRecording(queue: MonitoringQueue, properties: MonitoringProperties) =
        FilterRegistrationBean(RequestRecordingFilter(queue, properties)).apply { order = Ordered.HIGHEST_PRECEDENCE }
}
