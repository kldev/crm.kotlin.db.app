import { createFileRoute, redirect } from "@tanstack/react-router";
import { can, meQuery, type Role } from "#/features/auth/session";
import { QueuesPage } from "#/features/system/QueuesPage";

// System pages are for administrators (ADR-0012); the API refuses others too.
export const Route = createFileRoute("/_app/system/queues")({
	staticData: { wide: true },
	beforeLoad: async ({ context }) => {
		const me = await context.queryClient.query({ ...meQuery(), staleTime: "static" });
		if (!me || !can.seeSystem(me.role as Role)) throw redirect({ to: "/" });
	},
	component: QueuesPage,
});
