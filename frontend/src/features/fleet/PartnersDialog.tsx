import {
	Button,
	Chip,
	Input,
	Label,
	Modal,
	TextField,
	ToggleButton,
	ToggleButtonGroup,
	toast,
} from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { Eye, EyeOff, Plus } from "lucide-react";
import { forwardRef, useImperativeHandle, useState } from "react";
import type { PartnerResponse } from "#/api/models";
import { ApiError } from "#/components/ui";
import { useI18n } from "#/i18n";
import { partnersQuery, useSavePartner } from "./hooks";

export interface PartnersCommand {
	open: () => void;
}

type Kind = "REPAIR_SHOP" | "LEASING";

/**
 * The fleet's helper lists (ADR-0018): repair shops and leasing companies. A name is unique per kind ignoring case
 * and Polish letters; one a car has used is hidden, never deleted.
 */
export const PartnersDialog = forwardRef<PartnersCommand>((_, ref) => {
	const [open, setOpen] = useState(false);
	useImperativeHandle(ref, () => ({ open: () => setOpen(true) }), []);
	if (!open) return null;
	return <Content onClose={() => setOpen(false)} />;
});

function Content({ onClose }: { onClose: () => void }) {
	const { t } = useI18n();
	const [kind, setKind] = useState<Kind>("REPAIR_SHOP");
	const partners = useQuery(partnersQuery(kind));
	const [name, setName] = useState("");
	const [phone, setPhone] = useState("");
	const add = useSavePartner(undefined, () => {
		toast.success(t("Dodano", "Added"));
		setName("");
		setPhone("");
	});
	return (
		<Modal>
			<Modal.Backdrop isOpen onOpenChange={(o) => !o && onClose()}>
				<Modal.Container size="lg">
					<Modal.Dialog>
						<Modal.CloseTrigger />
						<Modal.Header>
							<Modal.Heading className="font-display text-2xl">
								{t("Warsztaty i leasing", "Repair shops & leasing")}
							</Modal.Heading>
						</Modal.Header>
						<Modal.Body>
							<div className="flex flex-col gap-4">
								<ToggleButtonGroup
									aria-label={t("Rodzaj", "Kind")}
									selectionMode="single"
									disallowEmptySelection
									size="sm"
									selectedKeys={new Set([kind])}
									onSelectionChange={(keys) => setKind([...keys][0] as Kind)}
								>
									<ToggleButton id="REPAIR_SHOP">{t("Warsztaty", "Repair shops")}</ToggleButton>
									<ToggleButton id="LEASING">
										{t("Firmy leasingowe", "Leasing companies")}
									</ToggleButton>
								</ToggleButtonGroup>
								<ul className="flex max-h-72 flex-col overflow-y-auto rounded-md border border-separator">
									{(partners.data ?? []).map((p) => (
										<PartnerRow key={p.id} partner={p} />
									))}
								</ul>
								<div className="flex flex-col gap-2 sm:flex-row sm:items-end">
									<TextField value={name} onChange={setName} fullWidth>
										<Label>{t("Nazwa", "Name")}</Label>
										<Input maxLength={120} />
									</TextField>
									<TextField value={phone} onChange={setPhone} className="sm:w-48">
										<Label>{t("Telefon", "Phone")}</Label>
										<Input maxLength={40} />
									</TextField>
									<Button
										isDisabled={name.trim() === ""}
										isPending={add.isPending}
										onPress={() =>
											add.mutate({
												kind,
												name: name.trim(),
												phone: phone.trim() || null,
												hidden: false,
											})
										}
									>
										<Plus className="size-4" />
										{t("Dodaj", "Add")}
									</Button>
								</div>
								<ApiError error={add.error} />
							</div>
						</Modal.Body>
					</Modal.Dialog>
				</Modal.Container>
			</Modal.Backdrop>
		</Modal>
	);
}

function PartnerRow({ partner }: { partner: PartnerResponse }) {
	const { t } = useI18n();
	const toggle = useSavePartner(partner.id);
	return (
		<li
			className={`flex items-center gap-3 border-b border-separator/60 px-3 py-2 last:border-b-0 ${partner.hidden ? "opacity-60" : ""}`}
		>
			<div className="flex min-w-0 flex-1 flex-col">
				<span className="truncate text-sm font-medium">{partner.name}</span>
				<span className="text-xs text-muted">{partner.phone ?? ""}</span>
			</div>
			{partner.cars > 0 ? (
				<Chip size="sm" variant="soft">
					{t(`${partner.cars} sam.`, `${partner.cars} cars`)}
				</Chip>
			) : null}
			<Button
				size="sm"
				variant="ghost"
				isIconOnly
				aria-label={partner.hidden ? t("Pokaż", "Show") : t("Ukryj", "Hide")}
				isPending={toggle.isPending}
				onPress={() =>
					toggle.mutate({
						kind: partner.kind,
						name: partner.name,
						phone: partner.phone ?? null,
						note: partner.note ?? null,
						hidden: !partner.hidden,
						rowVersion: partner.rowVersion,
					})
				}
			>
				{partner.hidden ? <Eye className="size-4" /> : <EyeOff className="size-4" />}
			</Button>
		</li>
	);
}
