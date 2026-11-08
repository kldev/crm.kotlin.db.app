import {
	CircleDot,
	ListChecks,
	type LucideIcon,
	Mail,
	NotebookPen,
	Phone,
	Presentation,
	UsersRound,
} from "lucide-react";
import type { I18n } from "#/i18n";
import { TIME_ZONE } from "#/i18n";

export const ACTIVITY_ICONS: Record<string, LucideIcon> = {
	CALL: Phone,
	EMAIL: Mail,
	MEETING: UsersRound,
	PRESENTATION: Presentation,
	NOTE: NotebookPen,
	TASK: ListChecks,
	OTHER: CircleDot,
};

export const activityName = (
	type: string,
	types: { type: string; namePl: string; nameEn: string }[] | undefined,
	{ lang }: Pick<I18n, "lang">,
) => {
	const found = types?.find((x) => x.type === type);
	return found ? (lang === "pl" ? found.namePl : found.nameEn) : type;
};

/** A moment in Warsaw time: "dziś 14:30", "jutro 9:00", "pt 7 lis, 9:00". */
export function when(iso: string, locale: string, t: I18n["t"]): string {
	const date = new Date(iso);
	const day = (d: Date) => new Intl.DateTimeFormat("en-CA", { timeZone: TIME_ZONE }).format(d);
	const time = new Intl.DateTimeFormat(locale, {
		timeZone: TIME_ZONE,
		hour: "2-digit",
		minute: "2-digit",
	}).format(date);
	const today = new Date();
	const tomorrow = new Date(today.getTime() + 86_400_000);
	const yesterday = new Date(today.getTime() - 86_400_000);
	if (day(date) === day(today)) return `${t("dziś", "today")} ${time}`;
	if (day(date) === day(tomorrow)) return `${t("jutro", "tomorrow")} ${time}`;
	if (day(date) === day(yesterday)) return `${t("wczoraj", "yesterday")} ${time}`;
	return new Intl.DateTimeFormat(locale, {
		timeZone: TIME_ZONE,
		weekday: "short",
		day: "numeric",
		month: "short",
		hour: "2-digit",
		minute: "2-digit",
	}).format(date);
}

/** Quick next steps: tomorrow at 9, in three days at 9, in a week at 9 (local time). */
export function quickMoment(days: number, hour = 9): string {
	const now = new Date();
	return new Date(
		now.getFullYear(),
		now.getMonth(),
		now.getDate() + days,
		hour,
		0,
		0,
	).toISOString();
}
