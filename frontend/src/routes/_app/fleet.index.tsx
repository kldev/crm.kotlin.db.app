import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { FleetPage } from "#/features/fleet/FleetPage";
import { AVAILABILITY } from "#/features/fleet/types";

export const Route = createFileRoute("/_app/fleet/")({
	staticData: { wide: true },
	validateSearch: z.object({
		q: z.string().optional(),
		status: z.string().optional(),
		availability: z.enum(AVAILABILITY).optional(),
		company: z.coerce.number().int().optional(),
		shop: z.coerce.number().int().optional(),
		archived: z.boolean().optional(),
		due: z.boolean().optional(),
	}),
	component: FleetPage,
});
