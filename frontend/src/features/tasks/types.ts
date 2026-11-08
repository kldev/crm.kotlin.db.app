import type { TaskResponse } from "#/api/models";
import type { Role } from "#/features/auth/session";
import type { I18n } from "#/i18n";
import { type Day, today } from "./dates";

export const TASK_SCOPES = ["MINE", "DEPARTMENT", "ALL"] as const;
export type TaskScope = (typeof TASK_SCOPES)[number];

export const TASK_VIEWS = ["calendar", "timeline"] as const;
export type TaskView = (typeof TASK_VIEWS)[number];

export const TIMELINE_SPANS = ["2w", "month"] as const;
export type TimelineSpan = (typeof TIMELINE_SPANS)[number];

export const scopeLabel = (s: TaskScope, { t }: Pick<I18n, "t">) =>
	({
		MINE: t("Tylko moje", "Only mine"),
		DEPARTMENT: t("Mój dział", "My department"),
		ALL: t("Wszystkie", "All"),
	})[s];

/**
 * Who may change a task (crm.task_require_editor): managers and administrators any, a salesperson the ones they
 * created or are assigned. Mirrored only to hide dead ends; the procedure decides.
 */
export const canEditTask = (task: TaskResponse, me: { id: number; role: Role }) =>
	me.role !== "SALES" || task.createdBy === me.id || task.assigneeUserId === me.id;

/** Open and past its last day. */
export const isOverdue = (task: TaskResponse, now: Day = today()) =>
	!task.done && task.endDate < now;

/** The look of a bar: open, overdue or done. Colors are the theme's tokens, never hex. */
export const barClass = (task: TaskResponse, now: Day = today()) =>
	task.done
		? "bg-[var(--obs-surface-subtle)] text-muted line-through decoration-1 border-[var(--obs-border)]"
		: isOverdue(task, now)
			? "bg-[var(--obs-danger-soft)] text-[var(--obs-danger)] border-[var(--obs-danger)]"
			: "bg-[var(--obs-info-soft)] text-[var(--obs-ink)] border-[var(--obs-info)]";
