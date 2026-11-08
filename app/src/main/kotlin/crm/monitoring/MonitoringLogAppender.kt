package crm.monitoring

import ch.qos.logback.classic.Level
import ch.qos.logback.classic.Logger
import ch.qos.logback.classic.LoggerContext
import ch.qos.logback.classic.spi.ILoggingEvent
import ch.qos.logback.classic.spi.ThrowableProxyUtil
import ch.qos.logback.core.AppenderBase
import org.slf4j.LoggerFactory
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication
import org.springframework.boot.context.event.ApplicationReadyEvent
import org.springframework.context.event.EventListener
import org.springframework.stereotype.Component
import java.time.Instant

/**
 * The application's log into the monitoring queue (ADR-0012): from CRM_MONITORING_LOG_LEVEL up, except the monitoring's
 * own entries (a failing write must not feed itself). Attached to the root logger once the application is ready; the
 * console log stays as it is.
 */
@Component
@ConditionalOnWebApplication
class MonitoringLogAppender(private val queue: MonitoringQueue, private val properties: MonitoringProperties) :
    AppenderBase<ILoggingEvent>() {

    private val threshold = Level.toLevel(properties.logLevel, Level.INFO)

    @EventListener(ApplicationReadyEvent::class)
    fun attach() {
        if (!properties.enabled) return
        val context = LoggerFactory.getILoggerFactory() as? LoggerContext ?: return
        this.context = context
        name = "monitoring"
        start()
        context.getLogger(Logger.ROOT_LOGGER_NAME).addAppender(this)
    }

    override fun append(event: ILoggingEvent) {
        if (!event.level.isGreaterOrEqual(threshold) || event.loggerName.startsWith("crm.monitoring")) return
        val level = when {
            event.level.isGreaterOrEqual(Level.ERROR) -> "ERROR"
            event.level.isGreaterOrEqual(Level.WARN) -> "WARN"
            else -> "INFO"
        }
        queue.add(
            RecordedLog(
                at = Instant.ofEpochMilli(event.timeStamp),
                level = level,
                source = event.loggerName,
                message = event.formattedMessage.take(4000),
                exception = event.throwableProxy?.let { ThrowableProxyUtil.asString(it).take(16_000) },
                requestPath = event.mdcPropertyMap[RequestRecordingFilter.REQUEST_PATH],
                traceId = event.mdcPropertyMap[RequestRecordingFilter.TRACE_ID],
            ),
        )
    }
}
