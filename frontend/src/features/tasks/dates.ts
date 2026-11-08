/*
 * Calendar days as ISO strings ("2026-11-08"), the shape the API speaks. The arithmetic runs in UTC, so a day is
 * always 24 hours and a daylight-saving change never moves a bar.
 */
export type Day = string;

const MS_DAY = 86_400_000;

export const parseDay = (day: Day): Date => {
	const [y, m, d] = day.split("-").map(Number);
	return new Date(Date.UTC(y, m - 1, d));
};

export const toDay = (date: Date): Day => date.toISOString().slice(0, 10);

export const addDays = (day: Day, n: number): Day =>
	toDay(new Date(parseDay(day).getTime() + n * MS_DAY));

/** Whole days from a to b (b - a). */
export const daysBetween = (a: Day, b: Day): number =>
	Math.round((parseDay(b).getTime() - parseDay(a).getTime()) / MS_DAY);

/** Today in the browser's calendar. */
export const today = (): Day => {
	const now = new Date();
	return toDay(new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate())));
};

/** Monday = 0 ... Sunday = 6. */
export const weekday = (day: Day): number => (parseDay(day).getUTCDay() + 6) % 7;

export const isWeekend = (day: Day): boolean => weekday(day) >= 5;

export const startOfWeek = (day: Day): Day => addDays(day, -weekday(day));

export const startOfMonth = (day: Day): Day => `${day.slice(0, 8)}01`;

export const addMonths = (day: Day, n: number): Day => {
	const d = parseDay(startOfMonth(day));
	d.setUTCMonth(d.getUTCMonth() + n);
	return toDay(d);
};

export const endOfMonth = (day: Day): Day => addDays(addMonths(day, 1), -1);

/** The days from..to, both included. */
export const range = (from: Day, to: Day): Day[] =>
	Array.from({ length: daysBetween(from, to) + 1 }, (_, i) => addDays(from, i));

/** The month view: whole weeks from the Monday before the 1st to the Sunday after the last day. */
export function monthWeeks(anchor: Day): Day[][] {
	const from = startOfWeek(startOfMonth(anchor));
	const to = addDays(startOfWeek(endOfMonth(anchor)), 6);
	const days = range(from, to);
	return Array.from({ length: days.length / 7 }, (_, w) => days.slice(w * 7, w * 7 + 7));
}

export const isValidDay = (value: string | undefined): value is Day =>
	value != null && /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(parseDay(value).getTime());

/**
 * Lanes for bars in one row: each item takes the first lane free on all its days, so overlapping bars stack and
 * the rest stay on top. Sorted by start, then the longer first, the way a calendar reads.
 */
export function packLanes<T extends { start: number; end: number }>(
	items: T[],
): (T & { lane: number })[] {
	const sorted = [...items].sort(
		(a, b) => a.start - b.start || b.end - b.start - (a.end - a.start),
	);
	const laneEnds: number[] = [];
	return sorted.map((item) => {
		let lane = laneEnds.findIndex((end) => end < item.start);
		if (lane === -1) lane = laneEnds.length;
		laneEnds[lane] = item.end;
		return { ...item, lane };
	});
}
