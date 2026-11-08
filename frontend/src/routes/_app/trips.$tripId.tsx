import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { TripPage } from "#/features/trips/TripPage";

export const Route = createFileRoute("/_app/trips/$tripId")({
	params: {
		parse: (p) => ({ tripId: z.coerce.number().int().parse(p.tripId) }),
		stringify: (p) => ({ tripId: String(p.tripId) }),
	},
	component: TripPage,
});
