package crm.storage

import org.springframework.boot.health.contributor.Health
import org.springframework.boot.health.contributor.HealthIndicator
import org.springframework.stereotype.Component

/** Readiness includes the attachments bucket (ADR-0009): without it a ticket page cannot show its files. */
@Component("storage")
class StorageHealthIndicator(private val storage: AttachmentStorage) : HealthIndicator {
    override fun health(): Health = try {
        storage.ping()
        Health.up().build()
    } catch (error: Exception) {
        Health.down().withDetail("error", error.javaClass.simpleName).build()
    }
}
