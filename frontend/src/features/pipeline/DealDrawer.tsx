import { Button, Chip, toast } from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { Trash2 } from "lucide-react";
import { forwardRef, useImperativeHandle, useMemo, useState } from "react";
import { z } from "zod";
import type { DealBoardParams, DealResponse } from "#/api/models";
import { ApiError, ConfirmDialog, FormDrawer } from "#/components/ui";
import { ClientPicker } from "#/features/clients/ClientPicker";
import { useAppForm } from "#/forms";
import { useI18n } from "#/i18n";
import { dealStagesQuery, useCreateDeal, useDeleteDeal, useMoveDeal, useUpdateDeal } from "./hooks";
import { LostReasonDialog } from "./LostReasonDialog";
import { stageAccent, stageName } from "./types";

export interface DealDrawerCommand {
	/** A new deal, in `stage` when added from a column. */
	create: (stage?: string) => void;
	edit: (deal: DealResponse) => void;
}

type Target = { deal?: DealResponse; stage?: string };

const CURRENCIES = ["PLN", "EUR", "USD"] as const;

/**
 * A deal in a drawer: the client (when new), what is sold, how much, when it should close. An open deal also moves
 * from here - the way to change the stage without dragging.
 */
export const DealDrawer = forwardRef<DealDrawerCommand, { board: DealBoardParams }>(
	({ board }, ref) => {
		const [target, setTarget] = useState<Target | null>(null);
		useImperativeHandle(
			ref,
			() => ({ create: (stage) => setTarget({ stage }), edit: (deal) => setTarget({ deal }) }),
			[],
		);
		if (!target) return null;
		return (
			<Content
				key={target.deal?.id ?? "new"}
				target={target}
				board={board}
				onClose={() => setTarget(null)}
			/>
		);
	},
);

function Content({
	target,
	board,
	onClose,
}: {
	target: Target;
	board: DealBoardParams;
	onClose: () => void;
}) {
	const i18n = useI18n();
	const { t } = i18n;
	const deal = target.deal;
	const stages = useQuery(dealStagesQuery());
	const [client, setClient] = useState<{ id: number; name: string } | undefined>(
		deal ? { id: deal.clientId, name: deal.clientName } : undefined,
	);
	const [clientMissing, setClientMissing] = useState(false);
	const [confirmDelete, setConfirmDelete] = useState(false);
	const [losing, setLosing] = useState(false);

	const schema = useMemo(
		() =>
			z.object({
				title: z
					.string()
					.trim()
					.min(1, t("Nazwa jest wymagana", "The name is required"))
					.max(200, t("Najwyżej 200 znaków", "At most 200 characters")),
				value: z
					.string()
					.trim()
					.refine(
						(v) => /^\d+([.,]\d{1,2})?$/.test(v.replace(/\s/g, "")),
						t("Kwota, np. 25000 albo 1999,99", "An amount, e.g. 25000 or 1999.99"),
					),
				currency: z.enum(CURRENCIES),
				expectedClose: z.iso.date(t("Podaj datę", "Enter a date")),
			}),
		[t],
	);

	const saved = (message: string) => () => {
		toast.success(message);
		onClose();
	};
	const create = useCreateDeal(saved(t("Dodano szansę", "Deal added")));
	const update = useUpdateDeal(deal?.id ?? 0, saved(t("Zapisano szansę", "Deal saved")));
	const move = useMoveDeal(board, (d) =>
		toast.success(
			t(
				`Przeniesiono do: ${stageName(stages.data?.find((s) => s.stage === d.stage) ?? { namePl: d.stage, nameEn: d.stage }, i18n)}`,
				`Moved to: ${stageName(stages.data?.find((s) => s.stage === d.stage) ?? { namePl: d.stage, nameEn: d.stage }, i18n)}`,
			),
		),
	);
	const remove = useDeleteDeal(saved(t("Usunięto szansę", "Deal deleted")));
	const mutation = deal ? update : create;

	const form = useAppForm({
		defaultValues: {
			title: deal?.title ?? "",
			value: deal ? String(Number(deal.value)) : "",
			currency: (deal?.currency ?? "PLN") as (typeof CURRENCIES)[number],
			expectedClose: deal?.expectedClose ?? "",
		},
		validators: { onChange: schema },
		onSubmit: ({ value }) => {
			const amount = Number(value.value.replace(/\s/g, "").replace(",", "."));
			if (deal)
				update.mutate({
					title: value.title.trim(),
					value: amount,
					currency: value.currency,
					expectedClose: value.expectedClose,
					offerId: deal.offerId ?? null,
					rowVersion: deal.rowVersion,
				});
			else if (!client) setClientMissing(true);
			else
				create.mutate({
					clientId: client.id,
					title: value.title.trim(),
					value: amount,
					currency: value.currency,
					expectedClose: value.expectedClose,
					stage: target.stage ?? null,
				});
		},
	});

	const current = stages.data?.find((s) => s.stage === deal?.stage);
	return (
		<>
			<FormDrawer
				title={deal ? deal.title : t("Nowa szansa sprzedaży", "New deal")}
				description={
					deal
						? `${deal.clientName} · ${deal.ownerName}`
						: t(
								"Szansa trafia do lejka klienta; jej właścicielem jest opiekun klienta.",
								"The deal joins the client's pipeline; the client's salesperson owns it.",
							)
				}
				onClose={onClose}
				onSubmit={() => void form.handleSubmit()}
			>
				<FormDrawer.Body>
					{deal && stages.data ? (
						<section className="flex flex-col gap-2">
							<p className="text-sm font-medium">{t("Etap", "Stage")}</p>
							<div className="flex flex-wrap gap-1.5">
								{stages.data.map((s) => {
									const active = s.stage === deal.stage;
									return (
										<button
											key={s.stage}
											type="button"
											aria-pressed={active}
											disabled={active || move.isPending}
											onClick={() =>
												s.stage === "LOST"
													? setLosing(true)
													: move.mutate(
															{ id: deal.id, stage: s.stage, rowVersion: deal.rowVersion },
															{ onSuccess: onClose },
														)
											}
											className={`flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs transition-colors ${active ? "border-[var(--obs-ink)] bg-[var(--obs-ink)] text-white" : "border-separator bg-[var(--obs-surface)] hover:bg-[var(--obs-surface-hover)]"}`}
										>
											<span
												className="size-2 rounded-full"
												style={{ background: stageAccent[s.stage] }}
											/>
											{stageName(s, i18n)}
										</button>
									);
								})}
							</div>
							{deal.lostReason ? (
								<p className="text-xs text-[var(--obs-danger)]">
									{t("Powód przegranej: ", "Lost because: ")}
									{deal.lostReason}
								</p>
							) : null}
							{current ? (
								<p className="text-xs text-muted">
									{t(
										`Prawdopodobieństwo ${current.probability}%`,
										`Probability ${current.probability}%`,
									)}
									{deal.offerNumber ? ` · ${t("oferta", "offer")} ${deal.offerNumber}` : ""}
								</p>
							) : null}
							<ApiError error={move.error} />
						</section>
					) : null}
					{!deal ? (
						<div className="flex flex-col gap-1">
							<ClientPicker
								required
								value={client}
								onChange={(c) => {
									setClient(c);
									setClientMissing(false);
								}}
							/>
							{clientMissing ? (
								<p className="text-xs text-danger">{t("Wybierz klienta", "Choose a client")}</p>
							) : null}
							{target.stage && stages.data ? (
								<Chip size="sm" variant="soft" className="mt-1 self-start">
									{stageName(
										stages.data.find((s) => s.stage === target.stage) ?? {
											namePl: target.stage,
											nameEn: target.stage,
										},
										i18n,
									)}
								</Chip>
							) : null}
						</div>
					) : null}
					<form.AppField name="title">
						{(f) => (
							<f.FormInput
								label={t("Co sprzedajemy", "What we sell")}
								placeholder={t("Wdrożenie CRM", "CRM roll-out")}
								autoFocus={!deal}
							/>
						)}
					</form.AppField>
					<div className="grid grid-cols-[1fr_7rem] gap-3">
						<form.AppField name="value">
							{(f) => <f.FormInput label={t("Wartość", "Value")} inputMode="decimal" />}
						</form.AppField>
						<form.AppField name="currency">
							{(f) => (
								<f.FormSelect
									label={t("Waluta", "Currency")}
									options={CURRENCIES.map((c) => ({ id: c, label: c }))}
								/>
							)}
						</form.AppField>
					</div>
					<form.AppField name="expectedClose">
						{(f) => <f.FormDate label={t("Przewidywane zamknięcie", "Expected close")} />}
					</form.AppField>
					{deal ? (
						<Button
							size="sm"
							variant="ghost"
							className="self-start"
							onPress={() => setConfirmDelete(true)}
						>
							<Trash2 className="size-4" />
							{t("Usuń szansę", "Delete deal")}
						</Button>
					) : null}
					<ApiError error={mutation.error} />
				</FormDrawer.Body>
				<FormDrawer.Footer isPending={mutation.isPending} />
			</FormDrawer>
			{deal ? (
				<>
					<ConfirmDialog
						isOpen={confirmDelete}
						title={t("Usunąć szansę?", "Delete the deal?")}
						description={t(
							"Tylko dla szans założonych przez pomyłkę - przegraną oznacz jako przegraną.",
							"Only for deals opened by mistake - mark a lost deal as lost.",
						)}
						confirmLabel={t("Usuń", "Delete")}
						isPending={remove.isPending}
						error={remove.error}
						onConfirm={() => remove.mutate({ id: deal.id, rowVersion: deal.rowVersion })}
						onClose={() => setConfirmDelete(false)}
					/>
					<LostReasonDialog
						deal={losing ? deal : null}
						board={board}
						onClose={() => setLosing(false)}
						onDone={onClose}
					/>
				</>
			) : null}
		</>
	);
}
