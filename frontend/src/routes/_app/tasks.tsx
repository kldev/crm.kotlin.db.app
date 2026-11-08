import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { TasksPage } from "#/features/tasks/TasksPage";
import { TASK_SCOPES, TASK_VIEWS, TIMELINE_SPANS } from "#/features/tasks/types";

export const Route = createFileRoute("/_app/tasks")({
	staticData: { wide: true },
	validateSearch: z.object({
		view: z.enum(TASK_VIEWS).optional(),
		scope: z.enum(TASK_SCOPES).optional(),
		department: z.string().optional(),
		done: z.enum(["open", "done"]).optional(),
		date: z.iso.date().optional(),
		span: z.enum(TIMELINE_SPANS).optional(),
	}),
	component: TasksPage,
});
