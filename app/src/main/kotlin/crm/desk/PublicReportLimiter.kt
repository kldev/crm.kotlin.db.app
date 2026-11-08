package crm.desk

import org.springframework.stereotype.Component
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.util.ArrayDeque

/**
 * Caps the tickets the public form accepts per minute, for the whole application (one sliding window). The form
 * needs no sign-in, so this is what keeps a script from filling the pool. In memory: each replica counts its own.
 */
@Component
class PublicReportLimiter(private val properties: DeskProperties) {
    private val clock: Clock = Clock.systemUTC()
    private val window = Duration.ofMinutes(1)
    private val accepted = ArrayDeque<Instant>()

    @Synchronized
    fun tryAcquire(): Boolean {
        val now = clock.instant()
        while (accepted.isNotEmpty() && accepted.peekFirst() <= now - window) accepted.pollFirst()
        if (accepted.size >= properties.publicReportsPerMinute) return false
        accepted.addLast(now)
        return true
    }
}

/** 429 from the public form. */
class TooManyPublicReportsException : RuntimeException("Too many tickets were sent in the last minute. Try again shortly.")
