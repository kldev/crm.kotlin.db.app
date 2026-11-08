import { Button, Card, Skeleton, ToggleButton, ToggleButtonGroup } from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { getRouteApi } from "@tanstack/react-router";
import { CalendarDays, ChevronLeft, ChevronRight, GanttChart, Plus } from "lucide-react";
import { useRef } from "react";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError, SelectFilter } from "#/components/ui";
import { useI18n } from "#/i18n";
import {
	addDays,
	addMonths,
	type Day,
	endOfMonth,
	monthWeeks,
	parseDay,
	startOfMonth,
	startOfWeek,
	today,
} from "./dates";
import { departmentsQuery, tasksQuery } from "./hooks";
import { MonthCalendar } from "./MonthCalendar";
import { TaskDrawer, type TaskDrawerCommand } from "./TaskDrawer";
import { TaskTimeline } from "./TaskTimeline";
import { isOverdue, scopeLabel, TASK_SCOPES, type TaskScope, type TimelineSpan } from "./types";

const route = getRouteApi("/_app/tasks");

/** The window the view shows: the month's whole weeks, or two weeks / a month of the timeline. */
function windowOf(view: "calendar" | "timeline", anchor: Day, span: TimelineSpan) {
	if (view === "calendar") {
		const weeks = monthWeeks(anchor);
		return { from: weeks[0][0], to: weeks.at(-1)?.[6] ?? anchor };
	}
	if (span === "month") return { from: startOfMonth(anchor), to: endOfMonth(anchor) };
	const from = startOfWeek(anchor);
	return { from, to: addDays(from, 13) };
}

/**
 * Tasks (ADR-0014) on a month calendar or a timeline by person. No kanban and no statuses: a task is open or done.
 * The filters, the view and the period live in the URL, so a link shows the same plan.
 */
export function TasksPage() {
	const { t, locale } = useI18n();
	const search = route.useSearch();
	const navigate = route.useNavigate();
	const drawer = useRef<TaskDrawerCommand>(null);
	const view = search.view ?? "calendar";
	const scope: TaskScope = search.scope ?? "ALL";
	const span: TimelineSpan = search.span ?? "2w";
	const anchor = search.date ?? today();
	const { from, to } = windowOf(view, anchor, span);
	const departments = useQuery(departmentsQuery());
	const query = useQuery(
		tasksQuery({
			from,
			to,
			scope,
			department: scope === "ALL" ? search.department : undefined,
			done: search.done == null ? undefined : search.done === "done",
		}),
	);
	const tasks = query.data ?? [];
	const now = today();
	const open = tasks.filter((x) => !x.done).length;
	const overdue = tasks.filter((x) => isOverdue(x, now)).length;

	const step = (direction: 1 | -1) => {
		const next =
			view === "calendar" || span === "month"
				? addMonths(anchor, direction)
				: addDays(anchor, 14 * direction);
		void navigate({ search: (s) => ({ ...s, date: next }), replace: true });
	};
	const format = (day: Day, options: Intl.DateTimeFormatOptions) =>
		new Intl.DateTimeFormat(locale, { ...options, timeZone: "UTC" }).format(parseDay(day));
	const period =
		view === "calendar" || span === "month"
			? format(anchor, { month: "long", year: "numeric" })
			: `${format(from, { day: "numeric", month: "short" })} – ${format(to, { day: "numeric", month: "short", year: "numeric" })}`;

	return (
		<>
			<PageHeader
				eyebrow="CRM"
				title={t("Zadania", "Tasks")}
				description={t(
					"Kto co robi i od kiedy do kiedy - na kalendarzu miesiąca albo na osi czasu po osobach i działach.",
					"Who does what, from when to when - on a month calendar or on a timeline by person and department.",
				)}
				actions={
					<Button onPress={() => drawer.current?.create()}>
						<Plus className="size-4" />
						{t("Nowe zadanie", "New task")}
					</Button>
				}
			/>
			<Card className="overflow-hidden p-0">
				<div className="flex flex-col gap-3 border-b border-separator p-4 xl:flex-row xl:items-center">
					<ToggleButtonGroup
						aria-label={t("Widok", "View")}
						selectionMode="single"
						disallowEmptySelection
						size="sm"
						selectedKeys={new Set([view])}
						onSelectionChange={(keys) => {
							const next = [...keys][0] as "calendar" | "timeline";
							void navigate({
								search: (s) => ({ ...s, view: next === "calendar" ? undefined : next }),
								replace: true,
							});
						}}
					>
						<ToggleButton id="calendar">
							<CalendarDays className="size-4" />
							{t("Kalendarz", "Calendar")}
						</ToggleButton>
						<ToggleButton id="timeline">
							<GanttChart className="size-4" />
							{t("Oś czasu", "Timeline")}
						</ToggleButton>
					</ToggleButtonGroup>
					<ToggleButtonGroup
						aria-label={t("Czyje zadania", "Whose tasks")}
						selectionMode="single"
						disallowEmptySelection
						size="sm"
						selectedKeys={new Set([scope])}
						onSelectionChange={(keys) => {
							const next = [...keys][0] as TaskScope;
							void navigate({
								search: (s) => ({
									...s,
									scope: next === "ALL" ? undefined : next,
									department: next === "ALL" ? s.department : undefined,
								}),
								replace: true,
							});
						}}
					>
						{TASK_SCOPES.map((s) => (
							<ToggleButton key={s} id={s}>
								{scopeLabel(s, { t })}
							</ToggleButton>
						))}
					</ToggleButtonGroup>
					{scope === "ALL" ? (
						<SelectFilter
							label={t("Dział", "Department")}
							className="w-full sm:w-56"
							value={search.department}
							options={(departments.data ?? []).map((d) => ({ id: d.name, label: d.name }))}
							onChange={(department) =>
								void navigate({ search: (s) => ({ ...s, department }), replace: true })
							}
						/>
					) : null}
					<SelectFilter
						label={t("Stan", "State")}
						value={search.done}
						options={[
							{ id: "open", label: t("Otwarte", "Open") },
							{ id: "done", label: t("Zrobione", "Done") },
						]}
						onChange={(done) =>
							void navigate({
								search: (s) => ({ ...s, done: done as "open" | "done" | undefined }),
								replace: true,
							})
						}
					/>
					<div className="flex items-center gap-2 xl:ml-auto">
						{view === "timeline" ? (
							<ToggleButtonGroup
								aria-label={t("Zakres osi", "Timeline span")}
								selectionMode="single"
								disallowEmptySelection
								size="sm"
								selectedKeys={new Set([span])}
								onSelectionChange={(keys) => {
									const next = [...keys][0] as TimelineSpan;
									void navigate({
										search: (s) => ({ ...s, span: next === "2w" ? undefined : next }),
										replace: true,
									});
								}}
							>
								<ToggleButton id="2w">{t("2 tygodnie", "2 weeks")}</ToggleButton>
								<ToggleButton id="month">{t("Miesiąc", "Month")}</ToggleButton>
							</ToggleButtonGroup>
						) : null}
						<Button
							size="sm"
							variant="secondary"
							onPress={() =>
								void navigate({ search: (s) => ({ ...s, date: undefined }), replace: true })
							}
						>
							{t("Dziś", "Today")}
						</Button>
						<Button
							isIconOnly
							size="sm"
							variant="ghost"
							aria-label={t("Wcześniej", "Earlier")}
							onPress={() => step(-1)}
						>
							<ChevronLeft className="size-4" />
						</Button>
						<span className="min-w-40 text-center font-display text-lg font-semibold capitalize">
							{period}
						</span>
						<Button
							isIconOnly
							size="sm"
							variant="ghost"
							aria-label={t("Później", "Later")}
							onPress={() => step(1)}
						>
							<ChevronRight className="size-4" />
						</Button>
					</div>
				</div>
				<div className="flex flex-wrap items-center gap-x-5 gap-y-1 border-b border-separator bg-[var(--obs-surface-subtle)] px-4 py-2 text-xs text-muted">
					<span>
						{t(`${tasks.length} zadań w widoku`, `${tasks.length} tasks in view`)} ·{" "}
						{t(`${open} otwartych`, `${open} open`)}
						{overdue > 0 ? (
							<span className="text-[var(--obs-danger)]">
								{" "}
								· {t(`${overdue} po terminie`, `${overdue} overdue`)}
							</span>
						) : null}
					</span>
					<span className="flex items-center gap-3 sm:ml-auto">
						<Swatch
							className="border-[var(--obs-info)] bg-[var(--obs-info-soft)]"
							label={t("Otwarte", "Open")}
						/>
						<Swatch
							className="border-[var(--obs-danger)] bg-[var(--obs-danger-soft)]"
							label={t("Po terminie", "Overdue")}
						/>
						<Swatch
							className="border-[var(--obs-border)] bg-[var(--obs-surface-subtle)]"
							label={t("Zrobione", "Done")}
						/>
					</span>
				</div>
				{query.isError ? (
					<div className="p-4">
						<ApiError error={query.error} />
					</div>
				) : query.isPending ? (
					<div className="flex flex-col gap-2 p-4">
						{Array.from({ length: 6 }, (_, i) => (
							<Skeleton key={i} className="h-20 rounded-md" />
						))}
					</div>
				) : view === "calendar" ? (
					<MonthCalendar
						anchor={anchor}
						tasks={tasks}
						onDay={(day) => drawer.current?.create({ start: day })}
						onTask={(task) => drawer.current?.edit(task)}
					/>
				) : tasks.length === 0 ? (
					<p className="p-10 text-center text-sm text-muted">
						{t("W tym okresie nie ma zadań.", "There are no tasks in this period.")}
					</p>
				) : (
					<TaskTimeline
						from={from}
						to={to}
						tasks={tasks}
						onCell={(day, person) => drawer.current?.create({ start: day, assignee: person })}
						onTask={(task) => drawer.current?.edit(task)}
					/>
				)}
			</Card>
			<TaskDrawer ref={drawer} />
		</>
	);
}

function Swatch({ className, label }: { className: string; label: string }) {
	return (
		<span className="flex items-center gap-1.5">
			<span className={`h-3 w-5 rounded-[3px] border-l-[3px] ${className}`} />
			{label}
		</span>
	);
}
