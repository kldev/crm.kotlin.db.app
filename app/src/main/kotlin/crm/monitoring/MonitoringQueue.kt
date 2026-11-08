package crm.monitoring

import org.springframework.stereotype.Component
import java.time.Instant
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.BlockingQueue
import java.util.concurrent.atomic.AtomicLong

data class RecordedRequest(
    val at: Instant,
    val method: String,
    val path: String,
    val status: Int,
    val elapsedMs: Long,
    val user: String?,
    val traceId: String?,
)

data class RecordedLog(
    val at: Instant,
    val level: String,
    val source: String,
    val message: String,
    val exception: String?,
    val requestPath: String?,
    val traceId: String?,
)

/**
 * Two bounded queues in memory (ADR-0012): a request or a log call only adds an entry, never touches the database.
 * When a queue is full the entry is dropped and counted - the status page shows the count.
 */
@Component
class MonitoringQueue(properties: MonitoringProperties) {
    val requests: BlockingQueue<RecordedRequest> = ArrayBlockingQueue(properties.queueCapacity)
    val logs: BlockingQueue<RecordedLog> = ArrayBlockingQueue(properties.queueCapacity)
    val droppedRequests = AtomicLong()
    val droppedLogs = AtomicLong()
    val capacity = properties.queueCapacity

    fun add(request: RecordedRequest) {
        if (!requests.offer(request)) droppedRequests.incrementAndGet()
    }

    fun add(log: RecordedLog) {
        if (!logs.offer(log)) droppedLogs.incrementAndGet()
    }
}
