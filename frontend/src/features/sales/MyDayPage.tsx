import {
	Button,
	Card,
	Checkbox,
	Chip,
	Skeleton,
	ToggleButton,
	ToggleButtonGroup,
	toast,
} from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { getRouteApi, Link } from "@tanstack/react-router";
import {
	AlarmClock,
	CalendarClock,
	CalendarPlus,
	CircleAlert,
	ListTodo,
	Snowflake,
} from "lucide-react";
import { useRef } from "react";
import type { DealResponse, TaskResponse } from "#/api/models";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError } from "#/components/ui";
import { useMe } from "#/features/auth/session";
import { StatTile } from "#/features/desk/charts/ChartKit";
import { amount, stageAccent } from "#/features/pipeline/types";
import { useSetTaskDone } from "#/features/tasks/hooks";
import { TaskDrawer, type TaskDrawerCommand } from "#/features/tasks/TaskDrawer";
import { useI18n } from "#/i18n";
import { problemText } from "#/i18n/problems";
import { type ActivityCommand, ActivityDialog } from "./ActivityDialog";
import { agendaQuery, followUpsQuery, horizon, startOfToday, withoutNextStepQuery } from "./hooks";
import { type NextStepCommand, NextStepDialog } from "./NextStepDialog";
import { when } from "./types";

const route = getRouteApi("/_app/my-day");

/**
 * A salesperson's day on one screen (ADR-0017): the follow-ups due (overdue first), the tasks that have started
 * (overdue ones always included) with what got done today, and the open deals nobody follows up. Every row is one
 * click from its action: done, reschedule, plan.
 */
export function MyDayPage() {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const me = useMe();
	const search = route.useSearch();
	const navigate = route.useNavigate();
	const range = search.range ?? "day";
	const scope = search.scope ?? "MINE";
	const { until, untilDay } = horizon(range);
	const doneSince = startOfToday();
	const followUps = useQuery(followUpsQuery(until, scope));
	const cold = useQuery(withoutNextStepQuery(scope));
	const agenda = useQuery(agendaQuery(untilDay, doneSince));
	const activityDialog = useRef<ActivityCommand>(null);
	const nextStepDialog = useRef<NextStepCommand>(null);
	const taskDrawer = useRef<TaskDrawerCommand>(null);
	const setDone = useSetTaskDone();

	const now = Date.now();
	const today = new Intl.DateTimeFormat("en-CA").format(new Date());
	const due = followUps.data ?? [];
	const overdueFollowUps = due.filter(
		(d) => d.nextStepAt && new Date(d.nextStepAt).getTime() < now,
	);
	const tasks = agenda.data ?? [];
	const openTasks = tasks.filter((x) => !x.done);
	const doneTasks = tasks.filter((x) => x.done);
	const overdueTasks = openTasks.filter((x) => x.endDate < today);

	const toggle = (task: TaskResponse) =>
		setDone.mutate(
			{ id: task.id, done: !task.done, rowVersion: task.rowVersion },
			{
				onSuccess: (x) =>
					toast.success(x.done ? t("Zrobione", "Done") : t("Znów otwarte", "Reopened")),
				onError: (e) => toast.danger(problemText(e, i18n)),
			},
		);

	return (
		<>
			<PageHeader
				eyebrow={t("Sprzedaż", "Sales")}
				title={t("Mój dzień", "My day")}
				description={new Intl.DateTimeFormat(locale, {
					weekday: "long",
					day: "numeric",
					month: "long",
				}).format(new Date())}
				actions={
					<div className="flex flex-wrap gap-2">
						<ToggleButtonGroup
							aria-label={t("Zakres", "Range")}
							selectionMode="single"
							disallowEmptySelection
							size="sm"
							selectedKeys={new Set([range])}
							onSelectionChange={(keys) => {
								const next = [...keys][0] as "day" | "week";
								void navigate({
									search: (s) => ({ ...s, range: next === "day" ? undefined : next }),
									replace: true,
								});
							}}
						>
							<ToggleButton id="day">{t("Dziś", "Today")}</ToggleButton>
							<ToggleButton id="week">{t("Ten tydzień", "This week")}</ToggleButton>
						</ToggleButtonGroup>
						{me.role === "SALES" ? null : (
							<ToggleButtonGroup
								aria-label={t("Czyje", "Whose")}
								selectionMode="single"
								disallowEmptySelection
								size="sm"
								selectedKeys={new Set([scope])}
								onSelectionChange={(keys) => {
									const next = [...keys][0] as "MINE" | "ALL";
									void navigate({
										search: (s) => ({ ...s, scope: next === "MINE" ? undefined : next }),
										replace: true,
									});
								}}
							>
								<ToggleButton id="MINE">{t("Moje", "Mine")}</ToggleButton>
								<ToggleButton id="ALL">{t("Zespołu", "Team's")}</ToggleButton>
							</ToggleButtonGroup>
						)}
					</div>
				}
			/>
			<div className="mb-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
				<StatTile
					icon={CircleAlert}
					tone={overdueFollowUps.length + overdueTasks.length > 0 ? "danger" : undefined}
					label={t("Zaległe", "Overdue")}
					value={String(overdueFollowUps.length + overdueTasks.length)}
					note={t(
						`${overdueFollowUps.length} follow-upów · ${overdueTasks.length} zadań`,
						`${overdueFollowUps.length} follow-ups · ${overdueTasks.length} tasks`,
					)}
				/>
				<StatTile
					icon={AlarmClock}
					label={
						range === "day"
							? t("Follow-upy na dziś", "Follow-ups today")
							: t("Follow-upy w tym tygodniu", "Follow-ups this week")
					}
					value={String(due.length - overdueFollowUps.length)}
				/>
				<StatTile
					icon={ListTodo}
					label={t("Zadania otwarte", "Open tasks")}
					value={String(openTasks.length)}
					note={t(`${doneTasks.length} zrobione dziś`, `${doneTasks.length} done today`)}
				/>
				<StatTile
					icon={Snowflake}
					tone={(cold.data?.length ?? 0) > 0 ? "warning" : undefined}
					label={t("Bez następnego kroku", "No next step")}
					value={String(cold.data?.length ?? 0)}
					note={t("otwarte szanse bez follow-upu", "open deals with no follow-up")}
				/>
			</div>

			<div className="grid gap-5 xl:grid-cols-2">
				<Section title={t("Follow-upy", "Follow-ups")} icon={AlarmClock} count={due.length}>
					{followUps.isError ? (
						<ApiError error={followUps.error} />
					) : followUps.isPending ? (
						<Rows />
					) : due.length === 0 ? (
						<Empty
							text={t(
								"Nic zaplanowanego - dobry moment na nowe kontakty.",
								"Nothing planned - a good time for new contacts.",
							)}
						/>
					) : (
						due.map((d) => (
							<FollowUpRow
								key={d.id}
								deal={d}
								showOwner={scope === "ALL"}
								onDone={() => activityDialog.current?.open(d)}
								onMove={() => nextStepDialog.current?.open(d)}
							/>
						))
					)}
				</Section>

				<Section title={t("Zadania", "Tasks")} icon={ListTodo} count={openTasks.length}>
					{agenda.isError ? (
						<ApiError error={agenda.error} />
					) : agenda.isPending ? (
						<Rows />
					) : openTasks.length === 0 && doneTasks.length === 0 ? (
						<Empty text={t("Brak zadań na ten okres.", "No tasks for this period.")} />
					) : (
						<>
							{openTasks.map((x) => (
								<TaskRow
									key={x.id}
									task={x}
									today={today}
									onToggle={() => toggle(x)}
									onOpen={() => taskDrawer.current?.edit(x)}
								/>
							))}
							{doneTasks.length > 0 ? (
								<>
									<p className="px-4 pt-3 pb-1 font-mono text-[11px] tracking-[0.08em] text-muted uppercase">
										{t("Zrobione dziś", "Done today")}
									</p>
									{doneTasks.map((x) => (
										<TaskRow
											key={x.id}
											task={x}
											today={today}
											onToggle={() => toggle(x)}
											onOpen={() => taskDrawer.current?.edit(x)}
										/>
									))}
								</>
							) : null}
						</>
					)}
				</Section>
			</div>

			<div className="mt-5">
				<Section
					title={t("Szanse bez następnego kroku", "Deals with no next step")}
					icon={Snowflake}
					count={cold.data?.length ?? 0}
				>
					{cold.isError ? (
						<ApiError error={cold.error} />
					) : cold.isPending ? (
						<Rows />
					) : (cold.data ?? []).length === 0 ? (
						<Empty
							text={t(
								"Każda otwarta szansa ma zaplanowany krok.",
								"Every open deal has a step planned.",
							)}
						/>
					) : (
						<div className="grid gap-x-6 lg:grid-cols-2">
							{(cold.data ?? []).map((d) => (
								<div
									key={d.id}
									className="flex items-center gap-3 border-b border-separator/60 px-4 py-2.5"
								>
									<span
										className="size-2.5 shrink-0 rounded-full"
										style={{ background: stageAccent[d.stage] }}
									/>
									<div className="flex min-w-0 flex-1 flex-col">
										<Link
											to="/pipeline/$dealId"
											params={{ dealId: d.id }}
											className="truncate text-sm font-medium hover:underline"
										>
											{d.title}
										</Link>
										<span className="truncate text-xs text-muted">
											{d.clientName} · {amount(d, locale)}
											{d.lastActivityAt
												? ` · ${t("ostatni kontakt", "last contact")} ${when(d.lastActivityAt, locale, t)}`
												: ` · ${t("bez kontaktu", "no contact yet")}`}
										</span>
									</div>
									<Button
										size="sm"
										variant="secondary"
										onPress={() => nextStepDialog.current?.open(d)}
									>
										<CalendarPlus className="size-4" />
										{t("Zaplanuj", "Plan")}
									</Button>
								</div>
							))}
						</div>
					)}
				</Section>
			</div>
			<ActivityDialog ref={activityDialog} />
			<NextStepDialog ref={nextStepDialog} />
			<TaskDrawer ref={taskDrawer} />
		</>
	);
}

function Section({
	title,
	icon: Icon,
	count,
	children,
}: {
	title: string;
	icon: typeof AlarmClock;
	count: number;
	children: React.ReactNode;
}) {
	return (
		<Card className="overflow-hidden p-0">
			<div className="flex items-center gap-2 border-b border-separator bg-[var(--obs-surface-subtle)] px-4 py-3">
				<Icon className="size-4 text-[var(--obs-champagne)]" />
				<h2 className="text-sm font-semibold text-foreground">{title}</h2>
				<span className="ml-auto rounded-full bg-[var(--obs-surface)] px-2 py-0.5 text-[11px] tabular-nums text-muted">
					{count}
				</span>
			</div>
			<div className="flex flex-col">{children}</div>
		</Card>
	);
}

function FollowUpRow({
	deal,
	showOwner,
	onDone,
	onMove,
}: {
	deal: DealResponse;
	showOwner: boolean;
	onDone: () => void;
	onMove: () => void;
}) {
	const { t, locale } = useI18n();
	const overdue = deal.nextStepAt != null && new Date(deal.nextStepAt).getTime() < Date.now();
	return (
		<div
			className={`flex items-start gap-3 border-b border-separator/60 px-4 py-3 last:border-b-0 ${overdue ? "bg-[var(--obs-danger-soft)]/40" : ""}`}
		>
			<span
				className={`mt-0.5 shrink-0 rounded-md px-2 py-1 text-[11px] font-semibold tabular-nums ${overdue ? "bg-[var(--obs-danger-soft)] text-[var(--obs-danger)]" : "bg-[var(--obs-surface-subtle)] text-[var(--obs-text-secondary)]"}`}
			>
				{deal.nextStepAt ? when(deal.nextStepAt, locale, t) : ""}
			</span>
			<div className="flex min-w-0 flex-1 flex-col gap-0.5">
				<span className="text-sm font-medium text-foreground">{deal.nextStep}</span>
				<span className="flex min-w-0 items-center gap-1.5 text-xs text-muted">
					<span
						className="size-2 shrink-0 rounded-full"
						style={{ background: stageAccent[deal.stage] }}
					/>
					<Link
						to="/pipeline/$dealId"
						params={{ dealId: deal.id }}
						className="truncate hover:underline"
					>
						{deal.title}
					</Link>
					<span className="truncate">
						· {deal.clientName} · {amount(deal, locale)}
						{showOwner ? ` · ${deal.ownerName}` : ""}
					</span>
				</span>
			</div>
			<div className="flex shrink-0 gap-1.5">
				<Button size="sm" onPress={onDone}>
					{t("Zrobione", "Done")}
				</Button>
				<Button
					size="sm"
					variant="ghost"
					isIconOnly
					aria-label={t("Przełóż", "Reschedule")}
					onPress={onMove}
				>
					<CalendarClock className="size-4" />
				</Button>
			</div>
		</div>
	);
}

function TaskRow({
	task,
	today,
	onToggle,
	onOpen,
}: {
	task: TaskResponse;
	today: string;
	onToggle: () => void;
	onOpen: () => void;
}) {
	const { t, locale } = useI18n();
	const late = !task.done && task.endDate < today;
	const date = (iso: string) =>
		new Intl.DateTimeFormat(locale, { day: "numeric", month: "short" }).format(
			new Date(`${iso}T00:00:00`),
		);
	return (
		<div className="flex items-start gap-3 border-b border-separator/60 px-4 py-2.5 last:border-b-0">
			<Checkbox
				aria-label={
					task.done ? t("Otwórz ponownie", "Reopen") : t("Oznacz jako zrobione", "Mark done")
				}
				isSelected={task.done}
				onChange={onToggle}
				className="mt-0.5"
			>
				<Checkbox.Content>
					<Checkbox.Control>
						<Checkbox.Indicator />
					</Checkbox.Control>
				</Checkbox.Content>
			</Checkbox>
			<button
				type="button"
				onClick={onOpen}
				className="flex min-w-0 flex-1 flex-col gap-0.5 text-left"
			>
				<span
					className={`text-sm ${task.done ? "text-muted line-through" : "font-medium text-foreground"}`}
				>
					{task.title}
				</span>
				<span className="flex flex-wrap items-center gap-x-2 text-xs text-muted">
					{late ? (
						<Chip size="sm" variant="soft" color="danger">
							{t(`termin minął ${date(task.endDate)}`, `overdue since ${date(task.endDate)}`)}
						</Chip>
					) : (
						<span>
							{task.startDate === task.endDate
								? date(task.endDate)
								: `${date(task.startDate)} – ${date(task.endDate)}`}
						</span>
					)}
					{task.dealTitle ? (
						<span>· {task.dealTitle}</span>
					) : task.clientName ? (
						<span>· {task.clientName}</span>
					) : null}
				</span>
			</button>
		</div>
	);
}

function Rows() {
	return (
		<div className="flex flex-col gap-2 p-4">
			<Skeleton className="h-12 rounded-md" />
			<Skeleton className="h-12 rounded-md" />
			<Skeleton className="h-12 rounded-md" />
		</div>
	);
}

function Empty({ text }: { text: string }) {
	return <p className="px-4 py-8 text-center text-sm text-muted">{text}</p>;
}
