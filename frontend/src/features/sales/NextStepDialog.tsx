import { Button, Input, Label, Modal, TextField, toast } from "@heroui/react";
import { forwardRef, useImperativeHandle, useState } from "react";
import type { DealResponse } from "#/api/models";
import { ApiError, DateTimeInput } from "#/components/ui";
import { useI18n } from "#/i18n";
import { useSetNextStep } from "./hooks";
import { quickMoment } from "./types";

export interface NextStepCommand {
	open: (deal: DealResponse) => void;
}

/** Plan, move or clear a deal's next step (ADR-0017): what and when, with quick picks for the usual horizons. */
export const NextStepDialog = forwardRef<NextStepCommand>((_, ref) => {
	const [deal, setDeal] = useState<DealResponse | null>(null);
	useImperativeHandle(ref, () => ({ open: setDeal }), []);
	if (!deal) return null;
	return <Content key={deal.id} deal={deal} onClose={() => setDeal(null)} />;
});

function Content({ deal, onClose }: { deal: DealResponse; onClose: () => void }) {
	const { t } = useI18n();
	const [text, setText] = useState(deal.nextStep ?? "");
	const [at, setAt] = useState(deal.nextStepAt ?? quickMoment(1));
	const save = useSetNextStep(deal.id, (d) => {
		toast.success(
			d.nextStep
				? t("Zaplanowano następny krok", "Next step planned")
				: t("Usunięto następny krok", "Next step cleared"),
		);
		onClose();
	});
	return (
		<Modal>
			<Modal.Backdrop isOpen onOpenChange={(open) => !open && onClose()}>
				<Modal.Container size="md">
					<Modal.Dialog>
						<Modal.CloseTrigger />
						<Modal.Header>
							<div className="flex flex-col gap-1">
								<Modal.Heading className="font-display text-2xl">
									{t("Następny krok", "Next step")}
								</Modal.Heading>
								<p className="text-sm text-muted">
									{deal.title} · {deal.clientName}
								</p>
							</div>
						</Modal.Header>
						<Modal.Body>
							<div className="flex flex-col gap-4">
								<TextField value={text} onChange={setText} fullWidth autoFocus>
									<Label>{t("Co dalej", "What next")}</Label>
									<Input
										maxLength={400}
										placeholder={t("Zadzwonić po decyzję…", "Call for the decision…")}
									/>
								</TextField>
								<DateTimeInput
									label={t("Kiedy", "When")}
									value={at}
									onChange={setAt}
									className="sm:max-w-xs"
								/>
								<div className="flex flex-wrap gap-2">
									<Button
										size="sm"
										variant="secondary"
										onPress={() => setAt(quickMoment(0, new Date().getHours() + 2))}
									>
										{t("Za 2 godziny", "In 2 hours")}
									</Button>
									<Button size="sm" variant="secondary" onPress={() => setAt(quickMoment(1))}>
										{t("Jutro 9:00", "Tomorrow 9:00")}
									</Button>
									<Button size="sm" variant="secondary" onPress={() => setAt(quickMoment(3))}>
										{t("Za 3 dni", "In 3 days")}
									</Button>
									<Button size="sm" variant="secondary" onPress={() => setAt(quickMoment(7))}>
										{t("Za tydzień", "In a week")}
									</Button>
								</div>
								<ApiError error={save.error} />
							</div>
						</Modal.Body>
						<Modal.Footer>
							{deal.nextStep ? (
								<Button
									variant="ghost"
									className="mr-auto"
									isPending={save.isPending}
									onPress={() =>
										save.mutate({ nextStep: null, nextStepAt: null, rowVersion: deal.rowVersion })
									}
								>
									{t("Usuń krok", "Clear")}
								</Button>
							) : null}
							<Button slot="close" variant="secondary">
								{t("Anuluj", "Cancel")}
							</Button>
							<Button
								isPending={save.isPending}
								isDisabled={text.trim() === "" || !at}
								onPress={() =>
									save.mutate({
										nextStep: text.trim(),
										nextStepAt: at,
										rowVersion: deal.rowVersion,
									})
								}
							>
								{t("Zapisz", "Save")}
							</Button>
						</Modal.Footer>
					</Modal.Dialog>
				</Modal.Container>
			</Modal.Backdrop>
		</Modal>
	);
}
