package crm.auth

import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.HttpMethod
import org.springframework.http.HttpStatus
import org.springframework.security.authentication.AuthenticationManager
import org.springframework.security.authentication.ProviderManager
import org.springframework.security.authentication.dao.DaoAuthenticationProvider
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity
import org.springframework.security.config.annotation.web.invoke
import org.springframework.security.config.http.SessionCreationPolicy
import org.springframework.security.core.userdetails.UserDetailsService
import org.springframework.security.core.userdetails.UsernameNotFoundException
import org.springframework.security.crypto.factory.PasswordEncoderFactories
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.security.web.SecurityFilterChain
import org.springframework.security.web.authentication.HttpStatusEntryPoint
import org.springframework.security.web.authentication.logout.HttpStatusReturningLogoutSuccessHandler
import org.springframework.security.web.context.HttpSessionSecurityContextRepository
import org.springframework.security.web.context.SecurityContextRepository
import org.springframework.security.web.csrf.CookieCsrfTokenRepository
import org.springframework.security.web.csrf.CsrfTokenRequestAttributeHandler

/**
 * ADR-0003: identity in Spring Security. Login with a JSON request (AuthController), the authenticated user is
 * kept in the HTTP session (cookie), CSRF token in the XSRF-TOKEN cookie sent back as the X-XSRF-TOKEN header.
 * Users and password hashes are read and written only through procedures.
 */
@Configuration
@EnableWebSecurity
class SecurityConfig {

    @Bean
    fun passwordEncoder(): PasswordEncoder = PasswordEncoderFactories.createDelegatingPasswordEncoder()

    @Bean
    fun userDetailsService(auth: AuthRepository): UserDetailsService = UserDetailsService { login ->
        auth.findForLogin(login) ?: throw UsernameNotFoundException("Unknown login")
    }

    @Bean
    fun authenticationManager(users: UserDetailsService, encoder: PasswordEncoder): AuthenticationManager =
        ProviderManager(DaoAuthenticationProvider(users).apply { setPasswordEncoder(encoder) })

    @Bean
    fun securityContextRepository(): SecurityContextRepository = HttpSessionSecurityContextRepository()

    @Bean
    fun securityFilterChain(http: HttpSecurity, contextRepository: SecurityContextRepository): SecurityFilterChain {
        http {
            csrf {
                // The client reads the XSRF-TOKEN cookie and sends its value as the X-XSRF-TOKEN header.
                // Plain (not masked) token: the cookie value itself is what the header must carry.
                csrfTokenRepository = CookieCsrfTokenRepository.withHttpOnlyFalse()
                csrfTokenRequestHandler = CsrfTokenRequestAttributeHandler()
            }
            securityContext { securityContextRepository = contextRepository }
            sessionManagement { sessionCreationPolicy = SessionCreationPolicy.IF_REQUIRED }
            formLogin { disable() }
            httpBasic { disable() }
            logout {
                logoutUrl = "/api/auth/logout"
                logoutSuccessHandler = HttpStatusReturningLogoutSuccessHandler(HttpStatus.NO_CONTENT)
            }
            exceptionHandling {
                // An API answers 401, it does not redirect to a login page.
                authenticationEntryPoint = HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)
            }
            authorizeHttpRequests {
                authorize("/api/auth/csrf", permitAll)
                authorize(HttpMethod.POST, "/api/auth/login", permitAll)
                // Answers 404 unless CRM_DEV_LOGIN=true (AuthController).
                authorize("/api/auth/dev-login", permitAll)
                authorize("/actuator/health/**", permitAll)
                // Error dispatches keep their real status (otherwise denyAll would turn every error into 403).
                authorize("/error", permitAll)
                authorize("/v3/api-docs/**", permitAll)
                authorize("/swagger-ui/**", permitAll)
                authorize("/swagger-ui.html", permitAll)
                authorize(HttpMethod.GET, "/api/users/**", hasAnyRole("ADMIN", "MANAGER"))
                authorize("/api/users/**", hasRole("ADMIN"))
                authorize("/api/**", authenticated)
                // The React app (static files and its client-side routes); its data comes from /api.
                authorize(HttpMethod.GET, "/**", permitAll)
                authorize(anyRequest, denyAll)
            }
        }
        return http.build()
    }
}
