package crm.desk.charts

import crm.auth.CrmUserDetails
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@Tag(name = "Desk charts")
@RestController
@RequestMapping("/api/desk/charts")
class DeskChartController(private val charts: DeskCharts) {

    @Operation(
        summary = "The numbers of the charts page: key figures, flow, SLA use, by category, queue now, agents and the " +
            "weekday x hour heatmap, for the last 7 / 30 days or 12 weeks, optionally of one category.",
    )
    @GetMapping
    fun getDeskCharts(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam(defaultValue = "DAYS_30") range: ChartRange,
        @RequestParam(required = false) categoryKey: String?,
    ): ChartData = charts.build(actor.id, range, categoryKey)
}
