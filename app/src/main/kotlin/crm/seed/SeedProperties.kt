package crm.seed

import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import org.springframework.boot.context.properties.ConfigurationProperties
import org.springframework.validation.annotation.Validated

/**
 * The one data seed (ADR-0004). Defaults are the performance data set; every value can be changed with env
 * (CRM_SEED_CLIENTS, CRM_SEED_SALES, ...). The password of all perf.* users has no default (CRM_SEED_PASSWORD).
 */
@Validated
@ConfigurationProperties("crm.seed")
data class SeedProperties(
    @field:Min(0) @field:Max(40_000_000) val clients: Int = 5_000_000,
    @field:Min(0) @field:Max(9_999) val admins: Int = 10,
    @field:Min(0) @field:Max(9_999) val managers: Int = 490,
    @field:Min(0) @field:Max(9_999) val sales: Int = 4_500,
    @field:Min(1) @field:Max(1_000) val teamSize: Int = 5,
    @field:Min(0) @field:Max(40_000_000) val projects: Int = 5_000_000,
    @field:Min(0) @field:Max(40_000_000) val comments: Int = 2_000_000,
    val randomSeed: Int = 42,
    @field:Min(1_000) @field:Max(2_000_000) val batchSize: Int = 500_000,
    val password: String? = null,
    /** Service desk (ADR-0007): generated tickets, only into an empty desk. CRM_SEED_DESK_TICKETS. */
    @field:Min(0) @field:Max(100_000) val deskTickets: Int = 200,
    /** CRM_SEED_DESK_ONLY=true: only the desk seed (idempotent), for a database whose CRM data is already seeded. */
    val deskOnly: Boolean = false,
)
