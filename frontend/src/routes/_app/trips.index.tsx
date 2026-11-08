import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { TripsPage } from "#/features/trips/TripsPage";
import { PURPOSES, TRIP_STATUSES } from "#/features/trips/types";

export const Route = createFileRoute("/_app/trips/")({
	staticData: { wide: true },
	validateSearch: z.object({
		scope: z.enum(["MINE", "TO_APPROVE", "ALL"]).optional(),
		status: z.enum(TRIP_STATUSES).optional(),
		purpose: z.enum(PURPOSES).optional(),
	}),
	component: TripsPage,
});
