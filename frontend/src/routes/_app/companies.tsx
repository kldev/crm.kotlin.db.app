import { createFileRoute } from "@tanstack/react-router";
import { CompaniesPage } from "#/features/companies/CompaniesPage";

export const Route = createFileRoute("/_app/companies")({
	staticData: { wide: true },
	component: CompaniesPage,
});
