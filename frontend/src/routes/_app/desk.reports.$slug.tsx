import { createFileRoute } from "@tanstack/react-router";
import { CategoryReportPage } from "#/features/desk/reports/CategoryReportPage";
import { categoryReportSearch } from "#/features/desk/reports/search";

export const Route = createFileRoute("/_app/desk/reports/$slug")({
	validateSearch: categoryReportSearch,
	component: CategoryReportPage,
});
