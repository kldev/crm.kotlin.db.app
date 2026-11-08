import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { PipelinePage } from "#/features/pipeline/PipelinePage";
import { DEAL_SCOPES } from "#/features/pipeline/types";

export const Route = createFileRoute("/_app/pipeline")({
	staticData: { wide: true },
	validateSearch: z.object({
		scope: z.enum(DEAL_SCOPES).optional(),
		q: z.string().optional(),
	}),
	component: PipelinePage,
});
