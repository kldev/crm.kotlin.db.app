import {
	Alert,
	Button,
	Input,
	Label,
	ListBox,
	Modal,
	Select,
	TextArea,
	TextField,
	toast,
} from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { type ReactNode, useState } from "react";
import type { CarResponse, HandoverResponse } from "#/api/models";
import { ApiError, DateInput } from "#/components/ui";
import { PersonPicker } from "#/features/users/PersonPicker";
import { useI18n } from "#/i18n";
import {
	carStatusesQuery,
	partnersQuery,
	useCancelHandover,
	useChangeHandover,
	useChangeStatus,
	useHandOver,
	useReturnCar,
	useSetFinancing,
} from "./hooks";

const todayIso = () =>
	new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Warsaw" }).format(new Date());

/** One dialog frame for the car's actions: a title, the fields, the error and Save. */
function ActionDialog({
	title,
	subtitle,
	onClose,
	onSave,
	isPending,
	isDisabled,
	error,
	saveLabel,
	danger,
	children,
}: {
	title: string;
	subtitle?: string;
	onClose: () => void;
	onSave: () => void;
	isPending?: boolean;
	isDisabled?: boolean;
	error?: unknown;
	saveLabel?: string;
	danger?: boolean;
	children: ReactNode;
}) {
	const { t } = useI18n();
	return (
		<Modal>
			<Modal.Backdrop isOpen onOpenChange={(o) => !o && onClose()}>
				<Modal.Container size="md">
					<Modal.Dialog>
						<Modal.CloseTrigger />
						<Modal.Header>
							<div className="flex flex-col gap-1">
								<Modal.Heading className="font-display text-2xl">{title}</Modal.Heading>
								{subtitle ? <p className="text-sm text-muted">{subtitle}</p> : null}
							</div>
						</Modal.Header>
						<Modal.Body>
							<div className="flex flex-col gap-4">
								{children}
								<ApiError error={error} />
							</div>
						</Modal.Body>
						<Modal.Footer>
							<Button slot="close" variant="secondary">
								{t("Anuluj", "Cancel")}
							</Button>
							<Button
								variant={danger ? "danger" : "primary"}
								isPending={isPending}
								isDisabled={isDisabled}
								onPress={onSave}
							>
								{saveLabel ?? t("Zapisz", "Save")}
							</Button>
						</Modal.Footer>
					</Modal.Dialog>
				</Modal.Container>
			</Modal.Backdrop>
		</Modal>
	);
}

function NumberField({
	label,
	value,
	onChange,
	suffix,
}: {
	label: string;
	value: string;
	onChange: (v: string) => void;
	suffix?: string;
}) {
	return (
		<TextField value={value} onChange={(v) => onChange(v.replace(/[^\d.,]/g, ""))} fullWidth>
			<Label>
				{label}
				{suffix ? <span className="text-muted"> ({suffix})</span> : null}
			</Label>
			<Input inputMode="decimal" />
		</TextField>
	);
}

function PickList({
	label,
	value,
	onChange,
	options,
}: {
	label: string;
	value: string | undefined;
	onChange: (v: string) => void;
	options: { id: string; label: string }[];
}) {
	const { t } = useI18n();
	return (
		<Select
			value={value ?? null}
			onChange={(k) => k != null && onChange(String(k))}
			placeholder={t("Wybierz…", "Select…")}
			fullWidth
		>
			<Label>{label}</Label>
			<Select.Trigger>
				<Select.Value />
				<Select.Indicator />
			</Select.Trigger>
			<Select.Popover>
				<ListBox>
					{options.map((o) => (
						<ListBox.Item key={o.id} id={o.id} textValue={o.label}>
							{o.label}
							<ListBox.ItemIndicator />
						</ListBox.Item>
					))}
				</ListBox>
			</Select.Popover>
		</Select>
	);
}

/** Change the car's status from a day; the repair-shop statuses ask for the shop. */
export function StatusDialog({ car, onClose }: { car: CarResponse; onClose: () => void }) {
	const { t, lang } = useI18n();
	const statuses = useQuery(carStatusesQuery());
	const shops = useQuery(partnersQuery("REPAIR_SHOP"));
	const [status, setStatus] = useState<string>();
	const [on, setOn] = useState(todayIso());
	const [shop, setShop] = useState<string | undefined>(
		car.repairShopId ? String(car.repairShopId) : undefined,
	);
	const [note, setNote] = useState("");
	const save = useChangeStatus(car.id, () => {
		toast.success(t("Zmieniono status", "Status changed"));
		onClose();
	});
	const needsShop = statuses.data?.find((s) => s.status === status)?.needsShop ?? false;
	return (
		<ActionDialog
			title={t("Zmień status", "Change status")}
			subtitle={`${car.name} · ${car.plate}`}
			onClose={onClose}
			isPending={save.isPending}
			isDisabled={!status || (needsShop && !shop)}
			error={save.error}
			onSave={() =>
				save.mutate({
					status: status ?? null,
					effectiveOn: on || null,
					repairShopId: needsShop ? Number(shop) : null,
					note: note || null,
					rowVersion: car.rowVersion,
				})
			}
		>
			<PickList
				label={t("Nowy status", "New status")}
				value={status}
				onChange={setStatus}
				options={(statuses.data ?? [])
					.filter((s) => s.status !== car.status)
					.map((s) => ({ id: s.status, label: lang === "pl" ? s.namePl : s.nameEn }))}
			/>
			{needsShop ? (
				<PickList
					label={t("Warsztat", "Repair shop")}
					value={shop}
					onChange={setShop}
					options={(shops.data ?? [])
						.filter((p) => !p.hidden)
						.map((p) => ({ id: String(p.id), label: p.name }))}
				/>
			) : null}
			<DateInput
				label={t("Od dnia", "From")}
				value={on}
				onChange={setOn}
				maxValue={todayIso()}
				minValue={car.statusSince}
			/>
			<TextField value={note} onChange={setNote} fullWidth>
				<Label>{t("Notatka", "Note")}</Label>
				<TextArea rows={2} maxLength={400} />
			</TextField>
		</ActionDialog>
	);
}

/** How the car is financed: unknown, bought, or leasing with its terms. */
export function FinancingDialog({ car, onClose }: { car: CarResponse; onClose: () => void }) {
	const { t } = useI18n();
	const leasings = useQuery(partnersQuery("LEASING"));
	const [kind, setKind] = useState(car.financing);
	const [purchase, setPurchase] = useState(car.purchaseDate ?? "");
	const [leasing, setLeasing] = useState(car.leasingId ? String(car.leasingId) : undefined);
	const [instalment, setInstalment] = useState(
		car.instalment != null ? String(car.instalment) : "",
	);
	const [currency, setCurrency] = useState(car.currency ?? "PLN");
	const [start, setStart] = useState(car.leaseStart ?? "");
	const [months, setMonths] = useState(car.leaseMonths ? String(car.leaseMonths) : "36");
	const [contract, setContract] = useState(car.contractNo ?? "");
	const save = useSetFinancing(car.id, () => {
		toast.success(t("Zapisano finansowanie", "Financing saved"));
		onClose();
	});
	return (
		<ActionDialog
			title={t("Finansowanie", "Financing")}
			subtitle={`${car.name} · ${car.plate}`}
			onClose={onClose}
			isPending={save.isPending}
			error={save.error}
			onSave={() =>
				save.mutate({
					financing: kind,
					purchaseDate: kind === "PAID" ? purchase || null : null,
					leasingId: kind === "LEASING" && leasing ? Number(leasing) : null,
					instalment:
						kind === "LEASING" && instalment ? Number(instalment.replace(",", ".")) : null,
					currency: kind === "LEASING" ? currency : null,
					leaseStart: kind === "LEASING" ? start || null : null,
					leaseMonths: kind === "LEASING" && months ? Number(months) : null,
					contractNo: kind === "LEASING" ? contract || null : null,
					rowVersion: car.rowVersion,
				})
			}
		>
			<PickList
				label={t("Sposób", "Kind")}
				value={kind}
				onChange={setKind}
				options={[
					{ id: "UNKNOWN", label: t("Nieznane", "Unknown") },
					{ id: "PAID", label: t("Kupiony", "Bought") },
					{ id: "LEASING", label: t("Leasing", "Leasing") },
				]}
			/>
			{kind === "PAID" ? (
				<DateInput
					label={t("Data zakupu", "Purchase date")}
					value={purchase}
					onChange={setPurchase}
				/>
			) : null}
			{kind === "LEASING" ? (
				<>
					<PickList
						label={t("Firma leasingowa", "Leasing company")}
						value={leasing}
						onChange={setLeasing}
						options={(leasings.data ?? [])
							.filter((p) => !p.hidden)
							.map((p) => ({ id: String(p.id), label: p.name }))}
					/>
					<div className="grid grid-cols-[1fr_6rem] gap-3">
						<NumberField
							label={t("Rata miesięczna", "Monthly instalment")}
							value={instalment}
							onChange={setInstalment}
						/>
						<TextField value={currency} onChange={(v) => setCurrency(v.toUpperCase().slice(0, 3))}>
							<Label>{t("Waluta", "Currency")}</Label>
							<Input />
						</TextField>
					</div>
					<div className="grid grid-cols-2 gap-3">
						<DateInput label={t("Początek", "Start")} value={start} onChange={setStart} />
						<NumberField
							label={t("Miesięcy", "Months")}
							value={months}
							onChange={setMonths}
							suffix="1-120"
						/>
					</div>
					<TextField value={contract} onChange={setContract} fullWidth>
						<Label>{t("Numer umowy", "Contract number")}</Label>
						<Input maxLength={60} />
					</TextField>
				</>
			) : null}
		</ActionDialog>
	);
}

/** Hand the car over to a person from a day, until a day or open-ended, with the mileage and fuel. */
export function HandoverDialog({ car, onClose }: { car: CarResponse; onClose: () => void }) {
	const { t } = useI18n();
	const [holder, setHolder] = useState<{ id: number; name: string }>();
	const [from, setFrom] = useState(todayIso());
	const [until, setUntil] = useState("");
	const [mileage, setMileage] = useState("");
	const [fuel, setFuel] = useState("100");
	const [notes, setNotes] = useState("");
	const save = useHandOver(car.id, (h) => {
		toast.success(t("Przekazano samochód", "Car handed over"));
		if (h.warning?.startsWith("REPAIR_SHOP:"))
			toast.warning(
				t(
					`Samochód jest w serwisie: ${h.warning.slice(12)}`,
					`The car is at a repair shop: ${h.warning.slice(12)}`,
				),
			);
		onClose();
	});
	const atShop = ["TO_REPAIR_SHOP", "IN_REPAIR_SHOP", "READY_FOR_PICKUP"].includes(car.status);
	return (
		<ActionDialog
			title={t("Przekaż samochód", "Hand over")}
			subtitle={`${car.name} · ${car.plate}`}
			onClose={onClose}
			isPending={save.isPending}
			isDisabled={!holder || !from || mileage === ""}
			error={save.error}
			saveLabel={t("Przekaż", "Hand over")}
			onSave={() =>
				save.mutate({
					holderUserId: holder?.id ?? null,
					issueDate: from,
					plannedReturn: until || null,
					issueMileage: Number(mileage),
					issueFuel: Number(fuel),
					notes: notes || null,
				})
			}
		>
			{atShop ? (
				<Alert status="warning">
					<Alert.Content>
						<Alert.Description>
							{t(
								`Samochód jest w serwisie (${car.repairShopName ?? ""}).`,
								`The car is at a repair shop (${car.repairShopName ?? ""}).`,
							)}
						</Alert.Description>
					</Alert.Content>
				</Alert>
			) : null}
			<PersonPicker label={t("Komu", "To whom")} value={holder} onChange={setHolder} />
			<div className="grid grid-cols-2 gap-3">
				<DateInput label={t("Od", "From")} value={from} onChange={setFrom} />
				<DateInput
					label={t("Planowany zwrot", "Planned return")}
					value={until}
					onChange={setUntil}
					description={t("Puste - bezterminowo", "Empty - open-ended")}
				/>
			</div>
			<div className="grid grid-cols-2 gap-3">
				<NumberField
					label={t("Przebieg", "Mileage")}
					value={mileage}
					onChange={setMileage}
					suffix="km"
				/>
				<NumberField
					label={t("Paliwo / bateria", "Fuel / battery")}
					value={fuel}
					onChange={setFuel}
					suffix="%"
				/>
			</div>
			<TextField value={notes} onChange={setNotes} fullWidth>
				<Label>{t("Uwagi", "Notes")}</Label>
				<TextArea rows={2} maxLength={1000} />
			</TextField>
		</ActionDialog>
	);
}

/** Take the car back: the day, the mileage (not below the issue), the fuel. */
export function ReturnDialog({
	handover,
	onClose,
}: {
	handover: HandoverResponse;
	onClose: () => void;
}) {
	const { t } = useI18n();
	const [on, setOn] = useState(todayIso());
	const [mileage, setMileage] = useState(String(handover.issueMileage));
	const [fuel, setFuel] = useState(String(handover.issueFuel));
	const save = useReturnCar(handover.id, () => {
		toast.success(t("Przyjęto zwrot", "Return recorded"));
		onClose();
	});
	return (
		<ActionDialog
			title={t("Zwrot samochodu", "Take back")}
			subtitle={`${handover.holderName} · ${handover.carName} · ${handover.plate}`}
			onClose={onClose}
			isPending={save.isPending}
			error={save.error}
			saveLabel={t("Przyjmij zwrot", "Record return")}
			onSave={() =>
				save.mutate({
					returnedOn: on,
					returnMileage: Number(mileage),
					returnFuel: Number(fuel),
					rowVersion: handover.rowVersion,
				})
			}
		>
			<DateInput
				label={t("Dzień zwrotu", "Return day")}
				value={on}
				onChange={setOn}
				minValue={handover.issueDate}
				maxValue={todayIso()}
			/>
			<div className="grid grid-cols-2 gap-3">
				<NumberField
					label={t("Przebieg", "Mileage")}
					value={mileage}
					onChange={setMileage}
					suffix={`≥ ${handover.issueMileage} km`}
				/>
				<NumberField
					label={t("Paliwo / bateria", "Fuel / battery")}
					value={fuel}
					onChange={setFuel}
					suffix="%"
				/>
			</div>
		</ActionDialog>
	);
}

/** Move the planned return or change the notes of a live handover. */
export function ChangeHandoverDialog({
	handover,
	onClose,
}: {
	handover: HandoverResponse;
	onClose: () => void;
}) {
	const { t } = useI18n();
	const [until, setUntil] = useState(handover.plannedReturn ?? "");
	const [notes, setNotes] = useState(handover.notes ?? "");
	const save = useChangeHandover(handover.id, () => {
		toast.success(t("Zapisano", "Saved"));
		onClose();
	});
	return (
		<ActionDialog
			title={t("Zmień przekazanie", "Change handover")}
			subtitle={`${handover.holderName} · ${handover.carName}`}
			onClose={onClose}
			isPending={save.isPending}
			error={save.error}
			onSave={() =>
				save.mutate({
					plannedReturn: until || null,
					notes: notes || null,
					rowVersion: handover.rowVersion,
				})
			}
		>
			<DateInput
				label={t("Planowany zwrot", "Planned return")}
				value={until}
				onChange={setUntil}
				minValue={handover.issueDate}
				description={t("Puste - bezterminowo", "Empty - open-ended")}
			/>
			<TextField value={notes} onChange={setNotes} fullWidth>
				<Label>{t("Uwagi", "Notes")}</Label>
				<TextArea rows={2} maxLength={1000} />
			</TextField>
		</ActionDialog>
	);
}

/** Cancel a handover entered by mistake, with a reason; it stays in the history. */
export function CancelHandoverDialog({
	handover,
	onClose,
}: {
	handover: HandoverResponse;
	onClose: () => void;
}) {
	const { t } = useI18n();
	const [reason, setReason] = useState("");
	const save = useCancelHandover(handover.id, () => {
		toast.success(t("Anulowano przekazanie", "Handover cancelled"));
		onClose();
	});
	return (
		<ActionDialog
			title={t("Anuluj przekazanie", "Cancel handover")}
			subtitle={`${handover.holderName} · ${handover.carName}`}
			onClose={onClose}
			isPending={save.isPending}
			isDisabled={reason.trim() === ""}
			error={save.error}
			danger
			saveLabel={t("Anuluj przekazanie", "Cancel handover")}
			onSave={() => save.mutate({ reason: reason.trim(), rowVersion: handover.rowVersion })}
		>
			<TextField value={reason} onChange={setReason} fullWidth autoFocus>
				<Label>{t("Powód", "Reason")}</Label>
				<TextArea rows={2} maxLength={400} />
			</TextField>
		</ActionDialog>
	);
}
