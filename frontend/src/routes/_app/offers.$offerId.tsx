import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { OfferDetailsPage } from "#/features/offers/OfferDetailsPage";

export const Route = createFileRoute("/_app/offers/$offerId")({
	params: {
		parse: (p) => ({ offerId: z.coerce.number().int().parse(p.offerId) }),
		stringify: (p) => ({ offerId: String(p.offerId) }),
	},
	component: OfferDetailsPage,
});
