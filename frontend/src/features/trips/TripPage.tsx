import {
	Alert,
	Button,
	Card,
	Chip,
	Input,
	Label,
	ListBox,
	Modal,
	Select,
	Skeleton,
	TextArea,
	TextField,
	toast,
} from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { getRouteApi, Link } from "@tanstack/react-router";
import { Ban, Banknote, CheckCheck, Pencil, Plus, Send, Trash2, Undo2 } from "lucide-react";
import { useRef, useState } from "react";
import type { ExpenseResponse, TripResponse } from "#/api/models";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError, DateInput, InfoList } from "#/components/ui";
import { useMe } from "#/features/auth/session";
import { useI18n } from "#/i18n";
import { problemText } from "#/i18n/problems";
import { tripExpensesQuery, tripQuery, useSaveExpenses, useTripStatus } from "./hooks";
import { TripDrawer, type TripDrawerCommand } from "./TripDrawer";
import {
	categoryLabel,
	EXPENSE_CATEGORIES,
	editable,
	money,
	PURPOSE_ICONS,
	type Purpose,
	purposeLabel,
	statusColor,
	statusLabel,
	type TripStatus,
	target,
	transportLabel,
} from "./types";

const route = getRouteApi("/_app/trips/$tripId");

/**
 * One business trip (ADR-0019): what for and where, the settlement worked out line by line, the expenses (editable
 * while the trip is planned or returned) and the next step of its way - submit, approve or return, pay.
 */
export function TripPage() {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const me = useMe();
	const manager = me.role === "ADMIN" || me.role === "MANAGER";
	const { tripId } = route.useParams();
	const trip = useQuery(tripQuery(tripId));
	const expenses = useQuery(tripExpensesQuery(tripId));
	const drawer = useRef<TripDrawerCommand>(null);
	const [returning, setReturning] = useState(false);
	const step = useTripStatus(tripId, (tr) => toast.success(statusLabel(tr.status, i18n)));

	if (trip.isError) return <ApiError error={trip.error} />;
	if (!trip.data) return <Skeleton className="h-64 rounded-lg" />;
	const tr = trip.data;
	const mine = tr.travellerUserId === me.id;
	const act = (action: string, note?: string) =>
		step.mutate(
			{ action, note: note ?? null, rowVersion: tr.rowVersion },
			{ onError: (e) => toast.danger(problemText(e, i18n)), onSuccess: () => setReturning(false) },
		);
	const when = (iso: string) =>
		new Intl.DateTimeFormat(locale, {
			dateStyle: "medium",
			timeStyle: "short",
			timeZone: "Europe/Warsaw",
		}).format(new Date(iso));
	const m = (v: number | string) => money(v, tr.currency, locale);
	const Icon = PURPOSE_ICONS[tr.purpose as Purpose] ?? PURPOSE_ICONS.OTHER;
	const ended = new Date(tr.endsAt).getTime() <= Date.now();

	return (
		<>
			<PageHeader
				eyebrow={
					<Link to="/trips" className="hover:underline">
						{t("Delegacje", "Business trips")}
					</Link>
				}
				title={target(tr)}
				description={`${tr.number} · ${tr.travellerName} · ${tr.destination}${tr.country !== "PL" ? ` (${tr.country})` : ""}`}
				actions={
					<div className="flex flex-wrap gap-2">
						{editable(tr) && (mine || manager) ? (
							<>
								<Button variant="secondary" onPress={() => drawer.current?.edit(tr)}>
									<Pencil className="size-4" />
									{t("Edytuj", "Edit")}
								</Button>
								<Button
									isDisabled={!ended}
									isPending={step.isPending}
									onPress={() => act("SUBMIT")}
								>
									<Send className="size-4" />
									{ended
										? t("Złóż rozliczenie", "Submit settlement")
										: t("Rozliczenie po powrocie", "Settle after return")}
								</Button>
							</>
						) : null}
						{tr.status === "PLANNED" && (mine || manager) ? (
							<Button variant="ghost" isPending={step.isPending} onPress={() => act("CANCEL")}>
								<Ban className="size-4" />
								{t("Anuluj", "Cancel")}
							</Button>
						) : null}
						{tr.status === "SUBMITTED" && manager && !mine ? (
							<>
								<Button isPending={step.isPending} onPress={() => act("APPROVE")}>
									<CheckCheck className="size-4" />
									{t("Zatwierdź", "Approve")}
								</Button>
								<Button variant="secondary" onPress={() => setReturning(true)}>
									<Undo2 className="size-4" />
									{t("Zwróć do poprawy", "Return")}
								</Button>
							</>
						) : null}
						{tr.status === "APPROVED" && manager && !mine ? (
							<Button isPending={step.isPending} onPress={() => act("PAY")}>
								<Banknote className="size-4" />
								{t("Wypłacono", "Mark paid")}
							</Button>
						) : null}
					</div>
				}
			/>
			{tr.status === "RETURNED" && tr.decisionNote ? (
				<Alert status="warning" className="mb-4">
					<Alert.Content>
						<Alert.Title>
							{t(
								`Zwrócona przez ${tr.decidedByName ?? ""}`,
								`Returned by ${tr.decidedByName ?? ""}`,
							)}
						</Alert.Title>
						<Alert.Description>{tr.decisionNote}</Alert.Description>
					</Alert.Content>
				</Alert>
			) : null}
			<div className="grid gap-5 lg:grid-cols-[1fr_24rem]">
				<div className="flex flex-col gap-5">
					<Card>
						<Card.Content>
							<InfoList
								items={[
									{
										label: t("Cel", "Purpose"),
										value: (
											<span className="flex items-center gap-2">
												<Icon className="size-4 text-[var(--obs-champagne)]" />
												{purposeLabel(tr.purpose, i18n)}
												{tr.clientId ? (
													<Link
														to="/clients/$clientId"
														params={{ clientId: tr.clientId }}
														className="hover:underline"
													>
														· {tr.clientName}
													</Link>
												) : null}
												{tr.projectId ? (
													<Link
														to="/projects/$projectId"
														params={{ projectId: tr.projectId }}
														className="hover:underline"
													>
														· {tr.projectName}
													</Link>
												) : null}
												{tr.eventName ? <span>· {tr.eventName}</span> : null}
											</span>
										),
									},
									{
										label: t("Kto", "Who"),
										value: `${tr.travellerName}${tr.travellerDepartment ? ` · ${tr.travellerDepartment}` : ""}`,
									},
									{
										label: t("Dokąd", "Where"),
										value: `${tr.destination}, ${i18n.lang === "pl" ? tr.countryNamePl : tr.countryNameEn}`,
									},
									{ label: t("Wyjazd", "Departure"), value: when(tr.startsAt) },
									{ label: t("Powrót", "Return"), value: when(tr.endsAt) },
									{
										label: t("Transport", "Transport"),
										value: `${transportLabel(tr.transport, i18n)}${tr.carPlate ? ` · ${tr.carPlate}` : ""}${tr.kilometres ? ` · ${tr.kilometres} km` : ""}`,
									},
									{ label: t("Spółka", "Company"), value: tr.legalEntityName },
									{
										label: t("Status", "Status"),
										value: (
											<Chip
												size="sm"
												variant="soft"
												color={statusColor[tr.status as TripStatus] ?? "default"}
											>
												{statusLabel(tr.status, i18n)}
											</Chip>
										),
									},
									...(tr.description
										? [{ label: t("Opis", "Description"), value: tr.description }]
										: []),
								]}
							/>
						</Card.Content>
					</Card>
					<Expenses
						trip={tr}
						rows={expenses.data ?? []}
						canEdit={editable(tr) && (mine || manager)}
					/>
				</div>
				<Card className="self-start">
					<Card.Header>
						<Card.Title className="text-base">{t("Rozliczenie", "Settlement")}</Card.Title>
					</Card.Header>
					<Card.Content className="flex flex-col gap-2 text-sm">
						<Line
							label={t(
								`Diety: ${Number(tr.diets).toLocaleString(locale)} × ${m(tr.dietRate)}`,
								`Per diems: ${Number(tr.diets).toLocaleString(locale)} × ${m(tr.dietRate)}`,
							)}
							value={m(tr.dietAmount)}
						/>
						{Number(tr.mealDeduction) > 0 ? (
							<Line
								label={t("Zapewnione posiłki", "Meals provided")}
								value={`− ${m(tr.mealDeduction)}`}
							/>
						) : null}
						{Number(tr.lumpAmount) > 0 ? (
							<Line
								label={t("Ryczałty (noclegi, dojazdy)", "Lump sums (nights, transport)")}
								value={m(tr.lumpAmount)}
							/>
						) : null}
						{Number(tr.mileageAmount) > 0 ? (
							<Line label={t("Kilometrówka", "Mileage")} value={m(tr.mileageAmount)} />
						) : null}
						<Line label={t("Wydatki", "Expenses")} value={m(tr.expensesAmount)} />
						<div className="my-1 border-t border-separator" />
						<Line label={t("Razem", "Total")} value={m(tr.total)} strong />
						{Number(tr.advance) > 0 ? (
							<Line label={t("Zaliczka", "Advance")} value={`− ${m(tr.advance)}`} />
						) : null}
						<div className="mt-1 rounded-md bg-[var(--obs-surface-subtle)] px-3 py-2">
							<Line
								label={
									Number(tr.toPay) < 0
										? t("Do zwrotu przez delegowanego", "To give back")
										: t("Do wypłaty", "To pay")
								}
								value={m(Math.abs(Number(tr.toPay)))}
								strong
							/>
						</div>
						{tr.hotelOverLimit ? (
							<p className="text-xs text-[var(--obs-warning)]">
								{t(
									"Hotel powyżej limitu za noc - wymaga zgody pracodawcy.",
									"A hotel night above the limit - needs the employer's consent.",
								)}
							</p>
						) : null}
						<p className="text-[11px] text-muted">
							{t(
								"Diety: do 8 h nic, 8-12 h połowa, ponad 12 h całość; za granicą reszta do 8 h - jedna trzecia.",
								"Per diems: under 8 h none, 8-12 h half, over 12 h full; abroad a rest up to 8 h - a third.",
							)}
						</p>
					</Card.Content>
				</Card>
			</div>
			<TripDrawer ref={drawer} />
			{returning ? (
				<ReturnDialog
					onClose={() => setReturning(false)}
					onReturn={(note) => act("RETURN", note)}
					isPending={step.isPending}
				/>
			) : null}
		</>
	);
}

function Line({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
	return (
		<div
			className={`flex items-baseline justify-between gap-3 ${strong ? "font-semibold text-foreground" : ""}`}
		>
			<span className={strong ? "" : "text-[var(--obs-text-secondary)]"}>{label}</span>
			<span className="figures tabular-nums">{value}</span>
		</div>
	);
}

function ReturnDialog({
	onClose,
	onReturn,
	isPending,
}: {
	onClose: () => void;
	onReturn: (note: string) => void;
	isPending: boolean;
}) {
	const { t } = useI18n();
	const [note, setNote] = useState("");
	return (
		<Modal>
			<Modal.Backdrop isOpen onOpenChange={(o) => !o && onClose()}>
				<Modal.Container size="sm">
					<Modal.Dialog>
						<Modal.CloseTrigger />
						<Modal.Header>
							<Modal.Heading className="font-display text-2xl">
								{t("Zwróć do poprawy", "Return for corrections")}
							</Modal.Heading>
						</Modal.Header>
						<Modal.Body>
							<TextField value={note} onChange={setNote} fullWidth autoFocus>
								<Label>{t("Co poprawić", "What to correct")}</Label>
								<TextArea rows={3} maxLength={400} />
							</TextField>
						</Modal.Body>
						<Modal.Footer>
							<Button slot="close" variant="secondary">
								{t("Anuluj", "Cancel")}
							</Button>
							<Button
								isDisabled={note.trim() === ""}
								isPending={isPending}
								onPress={() => onReturn(note.trim())}
							>
								{t("Zwróć", "Return")}
							</Button>
						</Modal.Footer>
					</Modal.Dialog>
				</Modal.Container>
			</Modal.Backdrop>
		</Modal>
	);
}

type Row = {
	category: string;
	description: string;
	spentOn: string;
	document: string;
	amount: string;
	nights: string;
};

/** The expenses as an editable list while the trip may change; saved as a whole. */
function Expenses({
	trip,
	rows,
	canEdit,
}: {
	trip: TripResponse;
	rows: ExpenseResponse[];
	canEdit: boolean;
}) {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const [draft, setDraft] = useState<Row[] | null>(null);
	const save = useSaveExpenses(trip.id, () => {
		toast.success(t("Zapisano wydatki", "Expenses saved"));
		setDraft(null);
	});
	const day = trip.startsAt.slice(0, 10);
	const start = () =>
		setDraft(
			rows.map((r) => ({
				category: r.category,
				description: r.description,
				spentOn: r.spentOn,
				document: r.document ?? "",
				amount: String(r.amount),
				nights: r.nights ? String(r.nights) : "",
			})),
		);
	const update = (i: number, patch: Partial<Row>) =>
		setDraft((d) => d?.map((r, j) => (j === i ? { ...r, ...patch } : r)) ?? null);
	return (
		<Card className="p-0">
			<div className="flex items-center justify-between border-b border-separator px-5 py-3">
				<h2 className="text-sm font-semibold">{t("Wydatki", "Expenses")}</h2>
				{canEdit && !draft ? (
					<Button size="sm" variant="secondary" onPress={start}>
						<Pencil className="size-4" />
						{t("Edytuj wydatki", "Edit expenses")}
					</Button>
				) : null}
			</div>
			{draft ? (
				<div className="flex flex-col gap-3 p-4">
					{draft.map((r, i) => (
						<div
							key={`${i}-${r.category}`}
							className="grid gap-2 rounded-md border border-separator p-3 sm:grid-cols-[9rem_1fr_9rem_7rem_auto] sm:items-end"
						>
							<Select value={r.category} onChange={(k) => k && update(i, { category: String(k) })}>
								<Label>{t("Rodzaj", "Kind")}</Label>
								<Select.Trigger>
									<Select.Value />
									<Select.Indicator />
								</Select.Trigger>
								<Select.Popover>
									<ListBox>
										{EXPENSE_CATEGORIES.map((c) => (
											<ListBox.Item key={c} id={c} textValue={categoryLabel(c, i18n)}>
												{categoryLabel(c, i18n)}
												<ListBox.ItemIndicator />
											</ListBox.Item>
										))}
									</ListBox>
								</Select.Popover>
							</Select>
							<TextField value={r.description} onChange={(v) => update(i, { description: v })}>
								<Label>{t("Opis", "Description")}</Label>
								<Input maxLength={200} />
							</TextField>
							<DateInput
								label={t("Dzień", "Day")}
								value={r.spentOn}
								onChange={(v) => update(i, { spentOn: v })}
							/>
							<TextField
								value={r.amount}
								onChange={(v) => update(i, { amount: v.replace(/[^\d.,]/g, "") })}
							>
								<Label>{`${t("Kwota", "Amount")} (${trip.currency})`}</Label>
								<Input inputMode="decimal" />
							</TextField>
							<Button
								isIconOnly
								variant="ghost"
								aria-label={t("Usuń", "Remove")}
								onPress={() => setDraft((d) => d?.filter((_, j) => j !== i) ?? null)}
							>
								<Trash2 className="size-4" />
							</Button>
							<TextField
								value={r.document}
								onChange={(v) => update(i, { document: v })}
								className="sm:col-span-2"
							>
								<Label>{t("Nr dokumentu", "Document no.")}</Label>
								<Input maxLength={60} />
							</TextField>
							{r.category === "HOTEL" ? (
								<TextField
									value={r.nights}
									onChange={(v) => update(i, { nights: v.replace(/\D/g, "") })}
								>
									<Label>{t("Noce", "Nights")}</Label>
									<Input inputMode="numeric" />
								</TextField>
							) : null}
						</div>
					))}
					<div className="flex flex-wrap gap-2">
						<Button
							size="sm"
							variant="secondary"
							onPress={() =>
								setDraft((d) => [
									...(d ?? []),
									{
										category: "OTHER",
										description: "",
										spentOn: day,
										document: "",
										amount: "",
										nights: "",
									},
								])
							}
						>
							<Plus className="size-4" />
							{t("Dodaj wydatek", "Add expense")}
						</Button>
						<span className="flex-1" />
						<Button size="sm" variant="ghost" onPress={() => setDraft(null)}>
							{t("Anuluj", "Cancel")}
						</Button>
						<Button
							size="sm"
							isPending={save.isPending}
							onPress={() =>
								save.mutate({
									items: draft.map((r) => ({
										category: r.category,
										description: r.description,
										spentOn: r.spentOn,
										document: r.document || null,
										amount: Number(r.amount.replace(",", ".")),
										nights: r.category === "HOTEL" && r.nights ? Number(r.nights) : null,
									})),
									rowVersion: trip.rowVersion,
								})
							}
						>
							{t("Zapisz wydatki", "Save expenses")}
						</Button>
					</div>
					<ApiError error={save.error} />
				</div>
			) : rows.length === 0 ? (
				<p className="px-5 py-6 text-sm text-muted">{t("Bez wydatków.", "No expenses.")}</p>
			) : (
				<ul className="flex flex-col">
					{rows.map((r) => (
						<li
							key={r.id}
							className="flex items-center gap-3 border-b border-separator/60 px-5 py-2.5 last:border-b-0"
						>
							<Chip size="sm" variant="soft">
								{categoryLabel(r.category, i18n)}
							</Chip>
							<span className="flex min-w-0 flex-1 flex-col">
								<span className="truncate text-sm">{r.description}</span>
								<span className="text-xs text-muted">
									{new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(
										new Date(`${r.spentOn}T00:00:00`),
									)}
									{r.document ? ` · ${r.document}` : ""}
									{r.nights ? ` · ${r.nights} ${t("noc.", "nights")}` : ""}
								</span>
							</span>
							<span className="figures text-sm tabular-nums">
								{money(r.amount, trip.currency, locale)}
							</span>
						</li>
					))}
				</ul>
			)}
		</Card>
	);
}
