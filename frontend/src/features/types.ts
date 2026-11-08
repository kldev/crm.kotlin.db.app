import type { I18n } from "#/i18n";

/*
 * Labels and colours of the enums of the API. The values mirror the CHECK constraints of the database
 * (V1__schemas_and_tables.sql, V3__teams_and_projects.sql); Record<...> makes the compiler ask for a label
 * (or a colour) when a value is added. Labels are functions of the language (ADR-0008), like desk/types.ts.
 */
type T = Pick<I18n, "t">;
export type ChipColor = "default" | "accent" | "success" | "warning" | "danger";

export const CLIENT_STATUSES = ["LEAD", "ACTIVE", "INACTIVE"] as const;
export type ClientStatus = (typeof CLIENT_STATUSES)[number];
export const clientStatusLabel = (status: string, { t }: T) =>
	(
		({
			LEAD: t("Potencjalny", "Lead"),
			ACTIVE: t("Aktywny", "Active"),
			INACTIVE: t("Nieaktywny", "Inactive"),
		}) satisfies Record<ClientStatus, string>
	)[status as ClientStatus] ?? status;
export const clientStatusColor: Record<ClientStatus, ChipColor> = {
	LEAD: "warning",
	ACTIVE: "success",
	INACTIVE: "default",
};

export const STAGES = ["NEW", "ACCEPTED", "ACTIVE", "ON_HOLD", "CLOSED", "DECLINED"] as const;
export type Stage = (typeof STAGES)[number];
export const stageLabel = (stage: string, { t }: T) =>
	(
		({
			NEW: t("Nowy", "New"),
			ACCEPTED: t("Przyjęty", "Accepted"),
			ACTIVE: t("Aktywny", "Active"),
			ON_HOLD: t("Wstrzymany", "On hold"),
			CLOSED: t("Zamknięty", "Closed"),
			DECLINED: t("Odrzucony", "Declined"),
		}) satisfies Record<Stage, string>
	)[stage as Stage] ?? stage;
export const stageColor: Record<Stage, ChipColor> = {
	NEW: "accent",
	ACCEPTED: "warning",
	ACTIVE: "success",
	ON_HOLD: "default",
	CLOSED: "default",
	DECLINED: "danger",
};

/**
 * Allowed stage moves - a copy of crm.project_stage_transitions (V3__teams_and_projects.sql), used only to
 * offer the right buttons. The procedure app.project_change_stage is the authority (51902 otherwise).
 */
export const NEXT_STAGES: Record<Stage, Stage[]> = {
	NEW: ["ACCEPTED", "DECLINED"],
	ACCEPTED: ["ACTIVE", "DECLINED"],
	ACTIVE: ["ON_HOLD", "CLOSED"],
	ON_HOLD: ["ACTIVE", "CLOSED"],
	CLOSED: [],
	DECLINED: [],
};
/** The button that moves a project to the stage. */
export const stageAction = (stage: Stage, { t }: T) =>
	(
		({
			NEW: t("Otwórz ponownie", "Reopen"),
			ACCEPTED: t("Przyjmij", "Accept"),
			ACTIVE: t("Rozpocznij", "Start"),
			ON_HOLD: t("Wstrzymaj", "Put on hold"),
			CLOSED: t("Zamknij", "Close"),
			DECLINED: t("Odrzuć", "Decline"),
		}) satisfies Record<Stage, string>
	)[stage];
export const isOpenStage = (stage: string) =>
	["NEW", "ACCEPTED", "ACTIVE", "ON_HOLD"].includes(stage);

export const ROLES = ["ADMIN", "MANAGER", "SALES"] as const;
export type RoleName = (typeof ROLES)[number];
export const roleLabel = (role: string, { t }: T) =>
	(
		({
			ADMIN: t("Admin", "Admin"),
			MANAGER: t("Manager", "Manager"),
			SALES: t("Sprzedawca", "Sales"),
		}) satisfies Record<RoleName, string>
	)[role as RoleName] ?? role;
export const roleColor: Record<RoleName, ChipColor> = {
	ADMIN: "danger",
	MANAGER: "accent",
	SALES: "default",
};

/** Cities of the seed; the filter offers them, the API accepts any city. */
export const CITIES = [
	"Warszawa",
	"Kraków",
	"Łódź",
	"Wrocław",
	"Poznań",
	"Gdańsk",
	"Szczecin",
	"Bydgoszcz",
	"Lublin",
	"Białystok",
	"Katowice",
	"Gdynia",
	"Częstochowa",
	"Radom",
	"Rzeszów",
	"Toruń",
	"Sosnowiec",
	"Kielce",
	"Gliwice",
	"Olsztyn",
];
