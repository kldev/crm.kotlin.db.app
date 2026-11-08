import { Button, Input, Label, Modal, TextArea, TextField, toast } from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { forwardRef, useImperativeHandle, useState } from "react";
import { getDeal } from "#/api/endpoints/deals/deals";
import type { DealResponse } from "#/api/models";
import { ApiError, DateTimeInput } from "#/components/ui";
import { useI18n } from "#/i18n";
import { activityTypesQuery, useAddActivity, useSetNextStep } from "./hooks";
import { ACTIVITY_ICONS, quickMoment } from "./types";

export interface ActivityCommand {
	/** Log what happened on the deal, and plan what comes next. */
	open: (deal: DealResponse) => void;
}

/**
 * Logging a contact the way a salesperson works (ADR-0017): what kind, a note, when (now unless changed) - and, in
 * the same breath, the next step. A follow-up that is done gets replaced by the next one, or cleared.
 */
export const ActivityDialog = forwardRef<ActivityCommand>((_, ref) => {
	const [deal, setDeal] = useState<DealResponse | null>(null);
	useImperativeHandle(ref, () => ({ open: setDeal }), []);
	if (!deal) return null;
	return <Content key={deal.id} deal={deal} onClose={() => setDeal(null)} />;
});

function Content({ deal, onClose }: { deal: DealResponse; onClose: () => void }) {
	const i18n = useI18n();
	const { t, lang } = i18n;
	const types = useQuery(activityTypesQuery());
	const [type, setType] = useState("CALL");
	const [note, setNote] = useState("");
	const [occurredAt, setOccurredAt] = useState(() => new Date().toISOString());
	const [nextStep, setNextStep] = useState(deal.nextStep ?? "");
	const [nextStepAt, setNextStepAt] = useState(deal.nextStepAt ?? quickMoment(1));
	const [planNext, setPlanNext] = useState(!deal.closed);
	const add = useAddActivity(deal.id);
	const next = useSetNextStep(deal.id);
	const busy = add.isPending || next.isPending;

	const save = async () => {
		try {
			await add.mutateAsync({ type, note, occurredAt });
			const change = deal.closed
				? null
				: planNext && nextStep.trim() && nextStepAt
					? { nextStep: nextStep.trim(), nextStepAt }
					: !planNext && deal.nextStep
						? { nextStep: null, nextStepAt: null }
						: null;
			if (change) {
				// Logging the activity changed the deal (its newest activity), so the next step needs its new rowVersion.
				const fresh = await getDeal(deal.id);
				await next.mutateAsync({ ...change, rowVersion: fresh.rowVersion });
			}
			toast.success(t("Zapisano aktywność", "Activity logged"));
			onClose();
		} catch {
			// The error is shown under the form.
		}
	};

	return (
		<Modal>
			<Modal.Backdrop isOpen onOpenChange={(open) => !open && onClose()}>
				<Modal.Container size="md">
					<Modal.Dialog>
						<Modal.CloseTrigger />
						<Modal.Header>
							<div className="flex flex-col gap-1">
								<Modal.Heading className="font-display text-2xl">
									{t("Zapisz kontakt", "Log a contact")}
								</Modal.Heading>
								<p className="text-sm text-muted">
									{deal.title} · {deal.clientName}
								</p>
							</div>
						</Modal.Header>
						<Modal.Body>
							<div className="flex flex-col gap-4">
								<fieldset className="flex flex-wrap gap-1.5">
									<legend className="sr-only">{t("Rodzaj", "Kind")}</legend>
									{(types.data ?? [])
										.filter((x) => x.type !== "TASK")
										.map((x) => {
											const Icon = ACTIVITY_ICONS[x.type] ?? ACTIVITY_ICONS.OTHER;
											const chosen = x.type === type;
											return (
												<button
													key={x.type}
													type="button"
													aria-pressed={chosen}
													onClick={() => setType(x.type)}
													className={`flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs transition-colors ${chosen ? "border-[var(--obs-ink)] bg-[var(--obs-ink)] text-white" : "border-separator hover:bg-[var(--obs-surface-hover)]"}`}
												>
													<Icon className="size-3.5" />
													{lang === "pl" ? x.namePl : x.nameEn}
												</button>
											);
										})}
								</fieldset>
								<TextField value={note} onChange={setNote} fullWidth autoFocus>
									<Label>{t("Co się wydarzyło", "What happened")}</Label>
									<TextArea
										rows={3}
										maxLength={1000}
										placeholder={t("Rozmowa z…, ustalenia…", "Talked to…, agreed…")}
									/>
								</TextField>
								<DateTimeInput
									label={t("Kiedy", "When")}
									value={occurredAt}
									onChange={setOccurredAt}
									className="sm:max-w-xs"
								/>
								{deal.closed ? null : (
									<section className="flex flex-col gap-3 rounded-lg border border-separator bg-[var(--obs-surface-subtle)] p-3">
										<label className="flex items-center gap-2 text-sm font-medium">
											<input
												type="checkbox"
												checked={planNext}
												onChange={(e) => setPlanNext(e.target.checked)}
												className="size-4 accent-[var(--obs-ink)]"
											/>
											{t("Następny krok", "Next step")}
										</label>
										{planNext ? (
											<>
												<TextField value={nextStep} onChange={setNextStep} fullWidth>
													<Label className="sr-only">{t("Co dalej", "What next")}</Label>
													<Input
														maxLength={400}
														placeholder={t("Zadzwonić po decyzję…", "Call for the decision…")}
													/>
												</TextField>
												<div className="flex flex-wrap items-end gap-2">
													<DateTimeInput
														label={t("Kiedy", "When")}
														value={nextStepAt}
														onChange={setNextStepAt}
														className="w-full sm:w-64"
													/>
													<Button
														size="sm"
														variant="secondary"
														onPress={() => setNextStepAt(quickMoment(1))}
													>
														{t("Jutro 9:00", "Tomorrow 9:00")}
													</Button>
													<Button
														size="sm"
														variant="secondary"
														onPress={() => setNextStepAt(quickMoment(3))}
													>
														{t("Za 3 dni", "In 3 days")}
													</Button>
													<Button
														size="sm"
														variant="secondary"
														onPress={() => setNextStepAt(quickMoment(7))}
													>
														{t("Za tydzień", "In a week")}
													</Button>
												</div>
											</>
										) : (
											<p className="text-xs text-muted">
												{t(
													"Bez następnego kroku szansa trafi na listę „bez kontynuacji”.",
													"Without a next step the deal lands on the “not followed up” list.",
												)}
											</p>
										)}
									</section>
								)}
								<ApiError error={add.error ?? next.error} />
							</div>
						</Modal.Body>
						<Modal.Footer>
							<Button slot="close" variant="secondary">
								{t("Anuluj", "Cancel")}
							</Button>
							<Button isPending={busy} isDisabled={note.trim() === ""} onPress={() => void save()}>
								{t("Zapisz", "Save")}
							</Button>
						</Modal.Footer>
					</Modal.Dialog>
				</Modal.Container>
			</Modal.Backdrop>
		</Modal>
	);
}
