import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { DealPage } from "#/features/sales/DealPage";

export const Route = createFileRoute("/_app/pipeline/$dealId")({
	params: {
		parse: (p) => ({ dealId: z.coerce.number().int().parse(p.dealId) }),
		stringify: (p) => ({ dealId: String(p.dealId) }),
	},
	component: DealPage,
});
