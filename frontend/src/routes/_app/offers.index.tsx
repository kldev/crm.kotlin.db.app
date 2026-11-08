import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { OffersPage } from "#/features/offers/OffersPage";
import { OFFER_STATUSES } from "#/features/offers/types";

export const Route = createFileRoute("/_app/offers/")({
	validateSearch: z.object({
		q: z.string().optional(),
		status: z.enum(OFFER_STATUSES).optional(),
		template: z.string().optional(),
		company: z.coerce.number().int().optional(),
	}),
	component: OffersPage,
});
