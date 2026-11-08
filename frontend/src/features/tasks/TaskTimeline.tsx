import type { TaskResponse } from "#/api/models";
import { UserAvatar } from "#/components/ui";
import { useI18n } from "#/i18n";
import { type Day, daysBetween, isWeekend, packLanes, range, today } from "./dates";
import { barClass } from "./types";

type Person = { id: number; name: string; department: string | null; tasks: TaskResponse[] };

const LANE = 30;

/**
 * The timeline: a row per person, grouped by department, the days across. Each task is a bar from its first to
 * its last day; a person's overlapping tasks stack in lanes. Weekends are shaded and today is a line. A click on
 * an empty day of a row adds a task for that person from that day.
 */
export function TaskTimeline({
	from,
	to,
	tasks,
	onCell,
	onTask,
}: {
	from: Day;
	to: Day;
	tasks: TaskResponse[];
	onCell: (day: Day, person: { id: number; name: string }) => void;
	onTask: (task: TaskResponse) => void;
}) {
	const { t, locale } = useI18n();
	const days = range(from, to);
	const now = today();
	const columns = `repeat(${days.length}, minmax(34px, 1fr))`;
	const noDepartment = t("Bez działu", "No department");

	const people = new Map<number, Person>();
	for (const task of tasks) {
		const p = people.get(task.assigneeUserId) ?? {
			id: task.assigneeUserId,
			name: task.assigneeName,
			department: task.assigneeDepartment ?? null,
			tasks: [],
		};
		p.tasks.push(task);
		people.set(p.id, p);
	}
	const groups = new Map<string, Person[]>();
	for (const p of [...people.values()].sort((a, b) => a.name.localeCompare(b.name, locale))) {
		const key = p.department ?? noDepartment;
		groups.set(key, [...(groups.get(key) ?? []), p]);
	}
	const ordered = [...groups.entries()].sort(([a], [b]) =>
		a === noDepartment ? 1 : b === noDepartment ? -1 : a.localeCompare(b, locale),
	);

	const dayFormat = new Intl.DateTimeFormat(locale, { weekday: "narrow", timeZone: "UTC" });
	const monthFormat = new Intl.DateTimeFormat(locale, { month: "long", timeZone: "UTC" });
	const months = days.reduce<{ label: string; span: number }[]>((acc, d) => {
		const label = monthFormat.format(new Date(`${d}T00:00:00Z`));
		const lastMonth = acc.at(-1);
		if (lastMonth?.label === label) lastMonth.span += 1;
		else acc.push({ label, span: 1 });
		return acc;
	}, []);

	return (
		<div className="overflow-x-auto">
			<div className="grid min-w-[900px]" style={{ gridTemplateColumns: "220px 1fr" }}>
				{/* Header: months, then the days. */}
				<div className="sticky left-0 z-20 row-span-2 border-b border-r border-separator bg-[var(--obs-surface-subtle)] px-4 py-2 text-[11px] font-semibold uppercase tracking-wider text-[var(--obs-text-secondary)]">
					{t("Osoba", "Person")}
				</div>
				<div
					className="grid border-b border-separator bg-[var(--obs-surface-subtle)]"
					style={{ gridTemplateColumns: columns }}
				>
					{months.map((m) => (
						<div
							key={m.label}
							style={{ gridColumn: `span ${m.span}` }}
							className="truncate border-r border-separator px-2 py-1 text-[11px] font-semibold capitalize text-[var(--obs-text-secondary)] last:border-r-0"
						>
							{m.label}
						</div>
					))}
				</div>
				<div
					className="grid border-b border-separator bg-[var(--obs-surface-subtle)]"
					style={{ gridTemplateColumns: columns }}
				>
					{days.map((d) => (
						<div
							key={d}
							className={`flex flex-col items-center py-1 text-[10px] leading-tight ${isWeekend(d) ? "text-muted" : "text-[var(--obs-text-secondary)]"}`}
						>
							<span className="uppercase">{dayFormat.format(new Date(`${d}T00:00:00Z`))}</span>
							<span
								className={`mt-0.5 grid size-5 place-items-center rounded-full tabular-nums ${d === now ? "bg-[var(--obs-ink)] font-semibold text-white" : ""}`}
							>
								{Number(d.slice(8))}
							</span>
						</div>
					))}
				</div>

				{ordered.map(([department, members]) => (
					<Group
						key={department}
						department={department}
						members={members}
						days={days}
						columns={columns}
						now={now}
						onCell={onCell}
						onTask={onTask}
					/>
				))}
			</div>
		</div>
	);
}

function Group({
	department,
	members,
	days,
	columns,
	now,
	onCell,
	onTask,
}: {
	department: string;
	members: Person[];
	days: Day[];
	columns: string;
	now: Day;
	onCell: (day: Day, person: { id: number; name: string }) => void;
	onTask: (task: TaskResponse) => void;
}) {
	const { t } = useI18n();
	const count = members.reduce((n, m) => n + m.tasks.length, 0);
	return (
		<>
			<div className="col-span-2 flex items-center gap-2 border-b border-separator bg-[var(--obs-surface-selected)] px-4 py-1.5">
				<span className="text-xs font-semibold uppercase tracking-wider text-[var(--obs-ink)]">
					{department}
				</span>
				<span className="text-[11px] text-muted">
					{t(`${members.length} os. · ${count} zad.`, `${members.length} people · ${count} tasks`)}
				</span>
			</div>
			{members.map((person) => (
				<Row
					key={person.id}
					person={person}
					days={days}
					columns={columns}
					now={now}
					onCell={onCell}
					onTask={onTask}
				/>
			))}
		</>
	);
}

function Row({
	person,
	days,
	columns,
	now,
	onCell,
	onTask,
}: {
	person: Person;
	days: Day[];
	columns: string;
	now: Day;
	onCell: (day: Day, person: { id: number; name: string }) => void;
	onTask: (task: TaskResponse) => void;
}) {
	const { t } = useI18n();
	const first = days[0];
	const lastIndex = days.length - 1;
	const placed = packLanes(
		person.tasks.map((task) => ({
			task,
			start: Math.max(0, daysBetween(first, task.startDate)),
			end: Math.min(lastIndex, daysBetween(first, task.endDate)),
		})),
	);
	const lanes = Math.max(1, ...placed.map((p) => p.lane + 1));
	const open = person.tasks.filter((x) => !x.done).length;
	return (
		<>
			<div className="sticky left-0 z-20 flex items-center gap-2.5 border-b border-r border-separator bg-[var(--obs-surface)] px-4">
				<UserAvatar name={person.name} />
				<div className="flex min-w-0 flex-col">
					<span className="truncate text-sm font-medium text-foreground">{person.name}</span>
					<span className="text-[11px] text-muted">
						{t(
							`${open} otwarte z ${person.tasks.length}`,
							`${open} open of ${person.tasks.length}`,
						)}
					</span>
				</div>
			</div>
			<div
				className="grid border-b border-separator"
				style={{
					gridTemplateColumns: columns,
					gridTemplateRows: `repeat(${lanes}, ${LANE}px)`,
					paddingBlock: 6,
				}}
			>
				{days.map((d, i) => (
					<button
						key={d}
						type="button"
						aria-label={t(
							`Dodaj zadanie: ${person.name}, ${d}`,
							`Add a task: ${person.name}, ${d}`,
						)}
						onClick={() => onCell(d, person)}
						style={{ gridColumn: i + 1, gridRow: `1 / span ${lanes}`, marginBlock: -6 }}
						className={`border-r border-[var(--obs-border-subtle)] transition-colors last:border-r-0 hover:bg-[var(--obs-surface-hover)] ${isWeekend(d) ? "bg-[var(--obs-surface-subtle)]" : ""} ${d === now ? "shadow-[inset_2px_0_0_var(--obs-champagne)]" : ""}`}
					/>
				))}
				{placed.map(({ task, start, end, lane }) => {
					const cutLeft = task.startDate < first;
					const cutRight = task.endDate > days[lastIndex];
					return (
						<button
							key={task.id}
							type="button"
							title={`${task.title} · ${task.startDate} → ${task.endDate}${task.clientName ? ` · ${task.clientName}` : ""}`}
							onClick={() => onTask(task)}
							style={{ gridColumn: `${start + 1} / ${end + 2}`, gridRow: lane + 1 }}
							className={`relative z-10 mx-[3px] my-[3px] flex min-w-0 items-center overflow-hidden border-l-[3px] px-2 text-left text-xs shadow-[0_0_0_1px_var(--obs-surface)] transition-[filter] hover:brightness-95 ${cutLeft ? "rounded-l-none" : "rounded-l-[4px]"} ${cutRight ? "rounded-r-none" : "rounded-r-[4px]"} ${barClass(task, now)}`}
						>
							<span className="truncate font-medium">{task.title}</span>
						</button>
					);
				})}
			</div>
		</>
	);
}
