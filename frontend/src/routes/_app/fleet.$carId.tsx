import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { CarDetailsPage } from "#/features/fleet/CarDetailsPage";

export const Route = createFileRoute("/_app/fleet/$carId")({
	params: {
		parse: (p) => ({ carId: z.coerce.number().int().parse(p.carId) }),
		stringify: (p) => ({ carId: String(p.carId) }),
	},
	validateSearch: z.object({ tab: z.enum(["data", "handovers", "history"]).optional() }),
	component: CarDetailsPage,
});
