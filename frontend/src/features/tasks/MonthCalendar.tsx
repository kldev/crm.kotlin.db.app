import { useState } from "react";
import type { TaskResponse } from "#/api/models";
import { useI18n } from "#/i18n";
import { type Day, daysBetween, isWeekend, monthWeeks, packLanes, today } from "./dates";
import { barClass } from "./types";

/** Bars shown per week before the rest fold into "+N". */
const LANES = 4;

/**
 * The month as whole weeks. A task is one bar across the days it lasts, cut at the week's edges; overlapping
 * tasks stack. A click on a day adds a task from it, a click on a bar opens the task.
 */
export function MonthCalendar({
	anchor,
	tasks,
	onDay,
	onTask,
}: {
	anchor: Day;
	tasks: TaskResponse[];
	onDay: (day: Day) => void;
	onTask: (task: TaskResponse) => void;
}) {
	const { locale } = useI18n();
	const weeks = monthWeeks(anchor);
	const month = anchor.slice(0, 7);
	const now = today();
	const weekdays = weeks[0].map((d) =>
		new Intl.DateTimeFormat(locale, { weekday: "short", timeZone: "UTC" }).format(
			new Date(`${d}T00:00:00Z`),
		),
	);
	return (
		<div className="overflow-x-auto">
			<div className="min-w-[760px]">
				<div className="grid grid-cols-7 border-b border-separator bg-[var(--obs-surface-subtle)]">
					{weekdays.map((w, i) => (
						<div
							key={w}
							className={`px-3 py-2 text-[11px] font-semibold uppercase tracking-wider ${i >= 5 ? "text-muted" : "text-[var(--obs-text-secondary)]"}`}
						>
							{w}
						</div>
					))}
				</div>
				{weeks.map((days) => (
					<Week
						key={days[0]}
						days={days}
						month={month}
						now={now}
						tasks={tasks}
						onDay={onDay}
						onTask={onTask}
					/>
				))}
			</div>
		</div>
	);
}

function Week({
	days,
	month,
	now,
	tasks,
	onDay,
	onTask,
}: {
	days: Day[];
	month: string;
	now: Day;
	tasks: TaskResponse[];
	onDay: (day: Day) => void;
	onTask: (task: TaskResponse) => void;
}) {
	const { t } = useI18n();
	const first = days[0];
	const last = days[6];
	const placed = packLanes(
		tasks
			.filter((task) => task.startDate <= last && task.endDate >= first)
			.map((task) => ({
				task,
				start: Math.max(0, daysBetween(first, task.startDate)),
				end: Math.min(6, daysBetween(first, task.endDate)),
			})),
	);
	const [expanded, setExpanded] = useState(false);
	const needed = placed.reduce((max, p) => Math.max(max, p.lane + 1), 0);
	const lanes = expanded ? Math.max(LANES, needed) : LANES;
	const shown = placed.filter((p) => p.lane < lanes);
	// What did not fit, per day: the "+N" under that day opens the whole week.
	const hidden = days.map(
		(_, i) => placed.filter((p) => p.lane >= lanes && p.start <= i && p.end >= i).length,
	);
	return (
		<div
			className="grid grid-cols-7 border-b border-separator last:border-b-0"
			style={{ gridTemplateRows: `30px repeat(${lanes}, 26px) 22px` }}
		>
			{days.map((day, i) => {
				const outside = !day.startsWith(month);
				const isToday = day === now;
				return (
					<button
						key={day}
						type="button"
						aria-label={t(`Dodaj zadanie od ${day}`, `Add a task from ${day}`)}
						onClick={() => onDay(day)}
						style={{ gridColumn: i + 1, gridRow: `1 / span ${lanes + 2}` }}
						className={`group flex items-start justify-end border-r border-separator px-2 pt-1.5 text-left transition-colors last:border-r-0 hover:bg-[var(--obs-surface-hover)] ${isWeekend(day) || outside ? "bg-[var(--obs-surface-subtle)]" : "bg-[var(--obs-surface)]"}`}
					>
						<span
							className={`grid size-6 place-items-center rounded-full text-xs tabular-nums ${isToday ? "bg-[var(--obs-ink)] font-semibold text-white" : outside ? "text-muted/60" : "text-[var(--obs-text-secondary)]"}`}
						>
							{Number(day.slice(8))}
						</span>
					</button>
				);
			})}
			{shown.map(({ task, start, end, lane }) => {
				const cutLeft = task.startDate < first;
				const cutRight = task.endDate > last;
				return (
					<button
						key={task.id}
						type="button"
						title={`${task.title} · ${task.assigneeName} · ${task.startDate} → ${task.endDate}`}
						onClick={() => onTask(task)}
						style={{ gridColumn: `${start + 1} / ${end + 2}`, gridRow: lane + 2 }}
						className={`relative z-10 mx-1 my-[2px] flex min-w-0 items-center gap-1.5 overflow-hidden border-l-[3px] px-2 text-left text-xs leading-none shadow-[0_0_0_1px_var(--obs-surface)] transition-[filter] hover:brightness-95 ${cutLeft ? "rounded-l-none" : "rounded-l-[4px]"} ${cutRight ? "rounded-r-none" : "rounded-r-[4px]"} ${barClass(task, now)}`}
					>
						<span className="truncate font-medium">{task.title}</span>
						<span className="hidden shrink-0 truncate text-[10px] opacity-70 sm:inline">
							{task.assigneeName}
						</span>
					</button>
				);
			})}
			{hidden.map((n, i) =>
				n > 0 ? (
					<button
						key={days[i]}
						type="button"
						onClick={() => setExpanded(true)}
						style={{ gridColumn: i + 1, gridRow: lanes + 2 }}
						className="z-10 mx-2 self-center text-left text-[11px] font-medium text-muted hover:text-foreground"
					>
						{t(`+${n} więcej`, `+${n} more`)}
					</button>
				) : null,
			)}
			{expanded && needed > LANES ? (
				<button
					type="button"
					onClick={() => setExpanded(false)}
					style={{ gridColumn: 7, gridRow: lanes + 2 }}
					className="z-10 mx-2 self-center text-right text-[11px] font-medium text-muted hover:text-foreground"
				>
					{t("Zwiń", "Collapse")}
				</button>
			) : null}
		</div>
	);
}
