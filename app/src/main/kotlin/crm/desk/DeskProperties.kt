package crm.desk

import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import org.springframework.boot.context.properties.ConfigurationProperties
import org.springframework.validation.annotation.Validated

/** Service desk settings (env only): CRM_DESK_PUBLIC_REPORTS_PER_MINUTE - tickets the public form accepts per minute. */
@Validated
@ConfigurationProperties("crm.desk")
data class DeskProperties(
    @field:Min(1) @field:Max(10000) val publicReportsPerMinute: Int = 30,
)
