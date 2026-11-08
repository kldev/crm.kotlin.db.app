import { Building2, Construction, type LucideIcon, MapPin, Presentation } from "lucide-react";
import type { TripResponse } from "#/api/models";
import type { I18n } from "#/i18n";

export const PURPOSES = ["CLIENT_VISIT", "TRADE_FAIR", "PROJECT_SITE", "OTHER"] as const;
export type Purpose = (typeof PURPOSES)[number];
export const TRIP_STATUSES = [
	"PLANNED",
	"SUBMITTED",
	"RETURNED",
	"APPROVED",
	"PAID",
	"CANCELLED",
] as const;
export type TripStatus = (typeof TRIP_STATUSES)[number];
export const TRANSPORTS = ["COMPANY_CAR", "PRIVATE_CAR", "TRAIN", "PLANE", "BUS", "OTHER"] as const;
export const EXPENSE_CATEGORIES = [
	"HOTEL",
	"TICKET",
	"FUEL",
	"PARKING",
	"TOLL",
	"TAXI",
	"OTHER",
] as const;

export const PURPOSE_ICONS: Record<Purpose, LucideIcon> = {
	CLIENT_VISIT: Building2,
	TRADE_FAIR: Presentation,
	PROJECT_SITE: Construction,
	OTHER: MapPin,
};

export const purposeLabel = (p: string, { t }: Pick<I18n, "t">) =>
	({
		CLIENT_VISIT: t("Wizyta u klienta", "Client visit"),
		TRADE_FAIR: t("Targi / wydarzenie", "Trade fair / event"),
		PROJECT_SITE: t("Projekt na miejscu", "Project site"),
		OTHER: t("Inne", "Other"),
	})[p as Purpose] ?? p;

export const statusLabel = (s: string, { t }: Pick<I18n, "t">) =>
	({
		PLANNED: t("Zaplanowana", "Planned"),
		SUBMITTED: t("Do akceptacji", "Submitted"),
		RETURNED: t("Do poprawy", "Returned"),
		APPROVED: t("Zatwierdzona", "Approved"),
		PAID: t("Wypłacona", "Paid"),
		CANCELLED: t("Anulowana", "Cancelled"),
	})[s as TripStatus] ?? s;

export const statusColor: Record<
	TripStatus,
	"default" | "accent" | "warning" | "success" | "danger"
> = {
	PLANNED: "default",
	SUBMITTED: "accent",
	RETURNED: "warning",
	APPROVED: "success",
	PAID: "success",
	CANCELLED: "danger",
};

export const transportLabel = (x: string, { t }: Pick<I18n, "t">) =>
	(
		({
			COMPANY_CAR: t("Samochód służbowy", "Company car"),
			PRIVATE_CAR: t("Prywatny samochód", "Private car"),
			TRAIN: t("Pociąg", "Train"),
			PLANE: t("Samolot", "Plane"),
			BUS: t("Autobus", "Bus"),
			OTHER: t("Inny", "Other"),
		}) as Record<string, string>
	)[x] ?? x;

export const categoryLabel = (x: string, { t }: Pick<I18n, "t">) =>
	(
		({
			HOTEL: t("Hotel", "Hotel"),
			TICKET: t("Bilet", "Ticket"),
			FUEL: t("Paliwo", "Fuel"),
			PARKING: t("Parking", "Parking"),
			TOLL: t("Autostrada", "Toll"),
			TAXI: t("Taksówka", "Taxi"),
			OTHER: t("Inne", "Other"),
		}) as Record<string, string>
	)[x] ?? x;

/** What the trip is for, in one line: the client, the event or the project. */
export const target = (trip: TripResponse) =>
	trip.clientName ?? trip.eventName ?? trip.projectName ?? trip.description;

export const money = (v: number | string, currency: string, locale: string) =>
	`${Number(v).toLocaleString(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ${currency}`;

/** A trip the traveller may still change (crm.trip_require): planned or returned for corrections. */
export const editable = (trip: TripResponse) =>
	trip.status === "PLANNED" || trip.status === "RETURNED";
