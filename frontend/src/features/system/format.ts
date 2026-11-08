import type { I18n } from "#/i18n";
import { TIME_ZONE } from "#/i18n";

export const ms = (v: number | null | undefined) => (v == null ? "—" : `${Math.round(v)} ms`);

export function dateTime(
	iso: string | null | undefined,
	{ locale }: Pick<I18n, "locale">,
	withSeconds = false,
) {
	if (!iso) return "—";
	// Local server times (no zone) are already Warsaw; instants (with Z) are shown in Warsaw.
	const value = /Z|[+-]\d\d:\d\d$/.test(iso) ? new Date(iso) : new Date(`${iso}`);
	return new Intl.DateTimeFormat(locale, {
		timeZone: /Z|[+-]\d\d:\d\d$/.test(iso) ? TIME_ZONE : undefined,
		dateStyle: "short",
		timeStyle: withSeconds ? "medium" : "short",
	}).format(value);
}

/** 2xx/3xx, 4xx, 5xx as the status colours with words. */
export function statusTone(status: number): "success" | "warning" | "danger" {
	if (status >= 500) return "danger";
	if (status >= 400) return "warning";
	return "success";
}
