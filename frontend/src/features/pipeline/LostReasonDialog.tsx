import { Button, Label, Modal, TextArea, TextField } from "@heroui/react";
import { useState } from "react";
import type { DealBoardParams, DealResponse } from "#/api/models";
import { ApiError } from "#/components/ui";
import { useI18n } from "#/i18n";
import { useMoveDeal } from "./hooks";

/** Dropping a card on "Lost" (or choosing it in the drawer) asks why: the procedure needs the reason (51197). */
export function LostReasonDialog({
	deal,
	board,
	onClose,
	onDone,
}: {
	deal: DealResponse | null;
	board: DealBoardParams;
	onClose: () => void;
	onDone?: () => void;
}) {
	const { t } = useI18n();
	const [reason, setReason] = useState("");
	const move = useMoveDeal(board, () => {
		setReason("");
		onClose();
		onDone?.();
	});
	return (
		<Modal>
			<Modal.Backdrop
				isOpen={deal != null}
				onOpenChange={(open) => {
					if (!open) {
						setReason("");
						move.reset();
						onClose();
					}
				}}
			>
				<Modal.Container size="sm">
					<Modal.Dialog>
						<Modal.CloseTrigger />
						<Modal.Header>
							<Modal.Heading className="font-display text-2xl">
								{t("Dlaczego przegrana?", "Why was it lost?")}
							</Modal.Heading>
						</Modal.Header>
						<Modal.Body>
							<div className="flex flex-col gap-3">
								<p className="text-sm text-muted">
									{deal ? `${deal.title} · ${deal.clientName}` : ""}
								</p>
								<TextField value={reason} onChange={setReason} fullWidth autoFocus>
									<Label>{t("Powód", "Reason")}</Label>
									<TextArea
										rows={3}
										maxLength={400}
										placeholder={t("Wybrali tańszą ofertę…", "They chose a cheaper offer…")}
									/>
								</TextField>
								<ApiError error={move.error} />
							</div>
						</Modal.Body>
						<Modal.Footer>
							<Button slot="close" variant="secondary">
								{t("Anuluj", "Cancel")}
							</Button>
							<Button
								variant="danger"
								isDisabled={reason.trim() === ""}
								isPending={move.isPending}
								onPress={() =>
									deal &&
									move.mutate({
										id: deal.id,
										stage: "LOST",
										lostReason: reason.trim(),
										rowVersion: deal.rowVersion,
									})
								}
							>
								{t("Oznacz jako przegraną", "Mark as lost")}
							</Button>
						</Modal.Footer>
					</Modal.Dialog>
				</Modal.Container>
			</Modal.Backdrop>
		</Modal>
	);
}
