package crm.migrate

import org.flywaydb.core.Flyway
import org.slf4j.LoggerFactory
import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.context.annotation.Profile
import org.springframework.stereotype.Component

/**
 * CRM_MODE=migrate (Spring profile `migrate`): Flyway has already migrated the database during startup
 * (spring.flyway.enabled=true in application-migrate.yml, migrator login). This runner reports the result;
 * the process then ends because there is no web server in this profile.
 */
@Component
@Profile("migrate")
class MigrateRunner(private val flyway: Flyway) : ApplicationRunner {
    private val log = LoggerFactory.getLogger(javaClass)

    override fun run(args: ApplicationArguments) {
        val current = flyway.info().current()
        log.info("Database migrated: version {} ({})", current?.version, current?.description)
    }
}
