package crm.monitoring

import org.slf4j.LoggerFactory
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication
import org.springframework.context.annotation.Configuration
import org.springframework.scheduling.annotation.EnableScheduling
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Component
import tools.jackson.databind.json.JsonMapper
import java.time.Instant
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import jakarta.annotation.PreDestroy

/** The state of one background job for the queues page. */
data class JobState(
    val name: String,
    val lastRunAt: Instant?,
    val lastResult: String?,
    val lastError: String?,
    val runs: Long,
)

class JobTracker(val name: String) {
    private val lastRun = AtomicReference<Instant?>(null)
    private val result = AtomicReference<String?>(null)
    private val error = AtomicReference<String?>(null)
    private val runs = AtomicLong()

    fun <T> run(describe: (T) -> String, work: () -> T): T? = try {
        val value = work()
        result.set(describe(value))
        error.set(null)
        value
    } catch (e: Exception) {
        error.set(e.javaClass.simpleName + (e.message?.let { ": ${it.take(300)}" } ?: ""))
        null
    } finally {
        lastRun.set(Instant.now())
        runs.incrementAndGet()
    }

    fun state() = JobState(name, lastRun.get(), result.get(), error.get(), runs.get())
}

@Configuration
@EnableScheduling
@ConditionalOnWebApplication
class MonitoringScheduling

/**
 * Writes the queues to the database every CRM_MONITORING_FLUSH_INTERVAL (ADR-0012), in batches of
 * CRM_MONITORING_WRITE_BATCH_SIZE, and once more at shutdown. A refused batch is dropped and counted, not retried: the
 * monitoring must never pile up memory because the database is down.
 */
@Component
@ConditionalOnWebApplication
class MonitoringWriter(
    private val queue: MonitoringQueue,
    private val monitoring: MonitoringRepository,
    private val properties: MonitoringProperties,
    private val json: JsonMapper,
) {
    private val log = LoggerFactory.getLogger(javaClass)
    val tracker = JobTracker("writer")
    val written = AtomicLong()
    val failed = AtomicLong()

    @Scheduled(fixedDelayString = "\${crm.monitoring.flush-interval:2s}", initialDelayString = "\${crm.monitoring.flush-interval:2s}")
    fun flush() {
        if (!properties.enabled) return
        tracker.run({ n: Int -> "$n written" }) { drain() }
    }

    @PreDestroy
    fun flushAtShutdown() = flush()

    @Synchronized
    private fun drain(): Int {
        var total = 0
        total += drain(queue.requests) { monitoring.writeRequests(json.writeValueAsString(it)) }
        total += drain(queue.logs) { monitoring.writeLogs(json.writeValueAsString(it)) }
        return total
    }

    private fun <T> drain(source: java.util.concurrent.BlockingQueue<T>, write: (List<T>) -> Int): Int {
        var total = 0
        while (true) {
            val batch = ArrayList<T>(properties.writeBatchSize)
            source.drainTo(batch, properties.writeBatchSize)
            if (batch.isEmpty()) return total
            try {
                total += write(batch)
            } catch (e: Exception) {
                failed.addAndGet(batch.size.toLong())
                log.warn("Monitoring batch of {} refused, dropped: {}", batch.size, e.javaClass.simpleName)
                return total
            }
            written.addAndGet(batch.size.toLong())
        }
    }
}

/**
 * Retention (ADR-0012): right after the start and every CRM_MONITORING_CLEANUP_INTERVAL, deletes answers and log
 * entries older than CRM_MONITORING_RETENTION in batches. Idempotent, so replicas need no lock.
 */
@Component
@ConditionalOnWebApplication
class MonitoringCleanup(private val monitoring: MonitoringRepository, private val properties: MonitoringProperties) {
    val tracker = JobTracker("cleanup")

    @Scheduled(initialDelayString = "PT10S", fixedDelayString = "\${crm.monitoring.cleanup-interval:1h}")
    fun run() {
        if (!properties.enabled) return
        tracker.run({ (requests, logs): Pair<Long, Long> -> "$requests answers, $logs log entries deleted" }) {
            monitoring.cleanup(Instant.now().minus(properties.retention), properties.cleanupBatchSize)
        }
    }
}
