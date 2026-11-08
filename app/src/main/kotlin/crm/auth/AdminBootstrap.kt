package crm.auth

import org.slf4j.LoggerFactory
import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.context.annotation.Profile
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.stereotype.Component

/** Creates the first ADMIN from CRM_ADMIN_LOGIN / CRM_ADMIN_PASSWORD when the database has no administrator. */
@Component
@Profile("!migrate & !seed")
class AdminBootstrap(
    private val properties: AuthProperties,
    private val auth: AuthRepository,
    private val passwordEncoder: PasswordEncoder,
) : ApplicationRunner {
    private val log = LoggerFactory.getLogger(javaClass)

    override fun run(args: ApplicationArguments) {
        val login = properties.adminLogin?.takeIf { it.isNotBlank() }
        val password = properties.adminPassword?.takeIf { it.isNotBlank() }
        if (login == null || password == null) {
            log.info("CRM_ADMIN_LOGIN / CRM_ADMIN_PASSWORD not set - no administrator bootstrap")
            return
        }
        if (auth.ensureAdmin(login, passwordEncoder.encode(password)!!)) {
            log.info("Administrator '{}' created", login)
        }
    }
}
