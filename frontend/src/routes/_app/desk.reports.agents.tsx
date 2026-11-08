import { createFileRoute } from "@tanstack/react-router";
import { AgentReportPage } from "#/features/desk/reports/AgentReportPage";
import { agentReportSearch } from "#/features/desk/reports/search";

export const Route = createFileRoute("/_app/desk/reports/agents")({
	validateSearch: agentReportSearch,
	component: AgentReportPage,
});
