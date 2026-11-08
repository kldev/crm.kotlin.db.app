import type { CarResponse, HandoverResponse } from "#/api/models";
import type { Role } from "#/features/auth/session";
import type { I18n } from "#/i18n";

export const AVAILABILITY = ["FREE", "HANDED_OVER", "OVERDUE"] as const;
export type Availability = (typeof AVAILABILITY)[number];

export const availabilityLabel = (a: string, { t }: Pick<I18n, "t">) =>
	({
		FREE: t("Wolny", "Free"),
		HANDED_OVER: t("Wydany", "Handed over"),
		OVERDUE: t("Po terminie zwrotu", "Overdue"),
	})[a as Availability] ?? a;

export const availabilityColor: Record<Availability, "success" | "accent" | "danger"> = {
	FREE: "success",
	HANDED_OVER: "accent",
	OVERDUE: "danger",
};

export const handoverStateLabel = (s: HandoverResponse["state"], { t }: Pick<I18n, "t">) =>
	(
		({
			CANCELLED: t("Anulowane", "Cancelled"),
			RETURNED: t("Zwrócony", "Returned"),
			PLANNED: t("Zaplanowane", "Planned"),
			OVERDUE: t("Po terminie", "Overdue"),
			CURRENT: t("W użyciu", "In use"),
		}) as Record<string, string>
	)[s] ?? s;

export const handoverStateColor = (
	s: string,
): "default" | "accent" | "danger" | "success" | "warning" =>
	s === "OVERDUE"
		? "danger"
		: s === "CURRENT"
			? "accent"
			: s === "PLANNED"
				? "warning"
				: s === "RETURNED"
					? "success"
					: "default";

export const statusName = (
	c: { statusNamePl: string; statusNameEn: string },
	{ lang }: Pick<I18n, "lang">,
) => (lang === "pl" ? c.statusNamePl : c.statusNameEn);

/** ADMIN and MANAGER run the fleet (crm.fleet_require_manager); mirrored only to hide dead ends. */
export const canManageFleet = (role: Role) => role === "ADMIN" || role === "MANAGER";

/** A deadline within 30 days (or past): the inspection or the insurance. */
export function dueSoon(date: string | null | undefined): "past" | "soon" | null {
	if (!date) return null;
	const days = (new Date(`${date}T00:00:00`).getTime() - Date.now()) / 86_400_000;
	return days < -1 ? "past" : days <= 30 ? "soon" : null;
}

export const carTitle = (c: Pick<CarResponse, "name" | "plate">) => `${c.name} · ${c.plate}`;
