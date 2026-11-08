import type { I18n } from "#/i18n";

/*
 * Formatting shared by the pages. The API sends UTC timestamps without a zone (datetime2) and ISO dates. Dates
 * follow the chosen language (the locale of useI18n()), money is always PLN.
 */

type Locale = I18n["locale"];

/** Intl formatters are costly to build, so one per locale and kind is kept. */
const cache = new Map<string, Intl.DateTimeFormat | Intl.RelativeTimeFormat>();
function cached<F extends Intl.DateTimeFormat | Intl.RelativeTimeFormat>(
	key: string,
	make: () => F,
): F {
	let value = cache.get(key);
	if (!value) {
		value = make();
		cache.set(key, value);
	}
	return value as F;
}

const dateFmt = (locale: Locale) =>
	cached(
		`date:${locale}`,
		() => new Intl.DateTimeFormat(locale, { day: "2-digit", month: "short", year: "numeric" }),
	);
const dateTimeFmt = (locale: Locale) =>
	cached(
		`datetime:${locale}`,
		() =>
			new Intl.DateTimeFormat(locale, {
				day: "2-digit",
				month: "short",
				year: "numeric",
				hour: "2-digit",
				minute: "2-digit",
			}),
	);
const relativeFmt = (locale: Locale) =>
	cached(`relative:${locale}`, () => new Intl.RelativeTimeFormat(locale, { numeric: "auto" }));
// Amounts are PLN whatever the language, so they keep the Polish grouping and symbol.
const moneyFmt = new Intl.NumberFormat("pl-PL", {
	style: "currency",
	currency: "PLN",
	maximumFractionDigits: 0,
});

const utc = (value: string) => new Date(value.endsWith("Z") ? value : `${value}Z`);

export const formatDate = (isoDate: string, locale: Locale) =>
	dateFmt(locale).format(new Date(`${isoDate}T00:00:00`));
export const formatDateTime = (timestamp: string, locale: Locale) =>
	dateTimeFmt(locale).format(utc(timestamp));
export const formatMoney = (amount: number) => moneyFmt.format(amount);

export function formatRelative(timestamp: string, locale: Locale): string {
	const seconds = (utc(timestamp).getTime() - Date.now()) / 1000;
	const steps: [Intl.RelativeTimeFormatUnit, number][] = [
		["year", 31_536_000],
		["month", 2_592_000],
		["week", 604_800],
		["day", 86_400],
		["hour", 3_600],
		["minute", 60],
	];
	for (const [unit, size] of steps) {
		if (Math.abs(seconds) >= size)
			return relativeFmt(locale).format(Math.round(seconds / size), unit);
	}
	return locale === "pl-PL" ? "przed chwilą" : "just now";
}

/** Days from today to an ISO date (negative = in the past). */
export function daysUntil(isoDate: string): number {
	const today = new Date();
	today.setHours(0, 0, 0, 0);
	return Math.round((new Date(`${isoDate}T00:00:00`).getTime() - today.getTime()) / 86_400_000);
}

export const todayIso = () => new Date().toISOString().slice(0, 10);
