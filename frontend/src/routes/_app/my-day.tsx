import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { MyDayPage } from "#/features/sales/MyDayPage";

export const Route = createFileRoute("/_app/my-day")({
	staticData: { wide: true },
	validateSearch: z.object({
		range: z.enum(["day", "week"]).optional(),
		scope: z.enum(["MINE", "ALL"]).optional(),
	}),
	component: MyDayPage,
});
