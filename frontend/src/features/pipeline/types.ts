import type { DealResponse, DealStageResponse } from "#/api/models";
import type { I18n } from "#/i18n";

export const DEAL_SCOPES = ["MINE", "ALL"] as const;
export type DealScope = (typeof DEAL_SCOPES)[number];

export const stageName = (
	s: Pick<DealStageResponse, "namePl" | "nameEn">,
	{ lang }: Pick<I18n, "lang">,
) => (lang === "pl" ? s.namePl : s.nameEn);

/** Amounts per currency, "120 000 PLN · 8 000 EUR": deals in different currencies are never added together. */
export function totals(deals: DealResponse[], locale: string, weight = false): string {
	const sums = new Map<string, number>();
	for (const d of deals) {
		const v = Number(d.value) * (weight ? d.probability / 100 : 1);
		sums.set(d.currency, (sums.get(d.currency) ?? 0) + v);
	}
	if (sums.size === 0) return `0 PLN`;
	return [...sums.entries()]
		.sort(([a], [b]) => (a === "PLN" ? -1 : b === "PLN" ? 1 : a.localeCompare(b)))
		.map(([c, v]) => `${Math.round(v).toLocaleString(locale)} ${c}`)
		.join(" · ");
}

export const amount = (d: Pick<DealResponse, "value" | "currency">, locale: string) =>
	`${Math.round(Number(d.value)).toLocaleString(locale)} ${d.currency}`;

/** The accent of a column: the funnel darkens towards the deal, won is green, lost is red. Theme tokens only. */
export const stageAccent: Record<string, string> = {
	LEAD: "var(--viz-seq-2)",
	QUALIFIED: "var(--viz-seq-3)",
	PROPOSAL: "var(--viz-seq-4)",
	NEGOTIATION: "var(--viz-seq-6)",
	WON: "var(--obs-success)",
	LOST: "var(--obs-danger)",
};
