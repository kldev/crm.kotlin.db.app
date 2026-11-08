import type { I18n } from "#/i18n";

export const OFFER_STATUSES = ["DRAFT", "SENT", "ACCEPTED", "REJECTED"] as const;
export type OfferStatus = (typeof OFFER_STATUSES)[number];

export const CURRENCIES = ["PLN", "EUR", "USD"] as const;
export const VAT_RATES = [23, 8, 5, 0] as const;

export const offerStatusLabel = (s: string, { t }: Pick<I18n, "t">) =>
	({
		DRAFT: t("Szkic", "Draft"),
		SENT: t("Wysłana", "Sent"),
		ACCEPTED: t("Przyjęta", "Accepted"),
		REJECTED: t("Odrzucona", "Rejected"),
	})[s as OfferStatus] ?? s;

export const offerStatusColor: Record<OfferStatus, "default" | "accent" | "success" | "danger"> = {
	DRAFT: "default",
	SENT: "accent",
	ACCEPTED: "success",
	REJECTED: "danger",
};

/**
 * Moves the procedure allows (app.offer_change_status): DRAFT -> SENT, SENT -> ACCEPTED | REJECTED | DRAFT.
 * Mirrored only to show the buttons; the procedure decides.
 */
export const NEXT_OFFER_STATUSES: Record<OfferStatus, OfferStatus[]> = {
	DRAFT: ["SENT"],
	SENT: ["ACCEPTED", "REJECTED", "DRAFT"],
	ACCEPTED: [],
	REJECTED: [],
};

export const offerAction = (s: OfferStatus, { t }: Pick<I18n, "t">) =>
	({
		SENT: t("Oznacz jako wysłaną", "Mark as sent"),
		ACCEPTED: t("Przyjęta przez klienta", "Accepted by the client"),
		REJECTED: t("Odrzucona przez klienta", "Rejected by the client"),
		DRAFT: t("Wróć do szkicu", "Back to draft"),
	})[s];

export function money(value: string | number, currency: string, locale: string): string {
	return `${Number(value).toLocaleString(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ${currency}`;
}

export const templateName = (
	t: { namePl?: string; nameEn?: string; templateNamePl?: string; templateNameEn?: string },
	{ lang }: Pick<I18n, "lang">,
) => (lang === "pl" ? (t.namePl ?? t.templateNamePl) : (t.nameEn ?? t.templateNameEn)) ?? "";
