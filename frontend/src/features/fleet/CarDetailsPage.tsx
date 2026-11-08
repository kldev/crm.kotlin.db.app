import { Button, Card, Chip, Dropdown, Label, Skeleton, Tabs, toast } from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { getRouteApi, Link, useNavigate } from "@tanstack/react-router";
import {
	ArrowLeftRight,
	CarFront,
	EllipsisVertical,
	Landmark,
	Pencil,
	RotateCcw,
	Trash2,
	Undo2,
	Wrench,
} from "lucide-react";
import { useRef, useState } from "react";
import type { HandoverResponse } from "#/api/models";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError, ConfirmDialog, EmptyState, InfoList, UserAvatar } from "#/components/ui";
import { useMe } from "#/features/auth/session";
import { useI18n } from "#/i18n";
import { problemText } from "#/i18n/problems";
import {
	CancelHandoverDialog,
	ChangeHandoverDialog,
	FinancingDialog,
	HandoverDialog,
	ReturnDialog,
	StatusDialog,
} from "./CarDialogs";
import { CarDrawer, type CarDrawerCommand } from "./CarDrawer";
import { Due } from "./FleetPage";
import { carHandoversQuery, carHistoryQuery, carQuery, useDeleteCar, useUndoReturn } from "./hooks";
import {
	type Availability,
	availabilityColor,
	availabilityLabel,
	canManageFleet,
	handoverStateColor,
	handoverStateLabel,
	statusName,
} from "./types";

const route = getRouteApi("/_app/fleet/$carId");

type Open =
	| { kind: "status" | "financing" | "handover" }
	| { kind: "return" | "change" | "cancel"; handover: HandoverResponse }
	| null;

/** One car (ADR-0018): who has it, its data and money, the handovers and the status history; the actions for managers. */
export function CarDetailsPage() {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const me = useMe();
	const manager = canManageFleet(me.role);
	const { carId } = route.useParams();
	const search = route.useSearch();
	const navigate = route.useNavigate();
	const goTo = useNavigate();
	const car = useQuery(carQuery(carId));
	const handovers = useQuery(carHandoversQuery(carId));
	const history = useQuery(carHistoryQuery(carId));
	const drawer = useRef<CarDrawerCommand>(null);
	const [open, setOpen] = useState<Open>(null);
	const [confirmDelete, setConfirmDelete] = useState(false);
	const remove = useDeleteCar(() => {
		toast.success(t("Usunięto samochód", "Car deleted"));
		void goTo({ to: "/fleet" });
	});
	const undo = useUndoReturn(() => toast.success(t("Cofnięto zwrot", "Return undone")));

	if (car.isError) return <ApiError error={car.error} />;
	if (!car.data) return <Skeleton className="h-64 rounded-lg" />;
	const c = car.data;
	const date = (iso: string | null | undefined) =>
		iso
			? new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(new Date(`${iso}T00:00:00`))
			: "—";
	const money = (v: number | null | undefined) =>
		v == null
			? "—"
			: `${Number(v).toLocaleString(locale, { minimumFractionDigits: 2 })} ${c.currency ?? ""}`;
	const live = (handovers.data ?? []).find((h) => h.state === "CURRENT" || h.state === "OVERDUE");
	const tab = search.tab ?? "data";

	return (
		<>
			<PageHeader
				eyebrow={
					<Link to="/fleet" className="hover:underline">
						{t("Flota", "Fleet")}
					</Link>
				}
				title={c.name}
				description={`${c.plate} · ${c.legalEntityName}`}
				actions={
					manager ? (
						<div className="flex flex-wrap gap-2">
							{live ? (
								<Button onPress={() => setOpen({ kind: "return", handover: live })}>
									<RotateCcw className="size-4" />
									{t("Przyjmij zwrot", "Take back")}
								</Button>
							) : c.status !== "FOR_SALE" && c.status !== "ARCHIVED" ? (
								<Button onPress={() => setOpen({ kind: "handover" })}>
									<ArrowLeftRight className="size-4" />
									{t("Przekaż", "Hand over")}
								</Button>
							) : null}
							<Button variant="secondary" onPress={() => setOpen({ kind: "status" })}>
								<Wrench className="size-4" />
								{t("Status", "Status")}
							</Button>
							<Dropdown>
								<Dropdown.Trigger>
									<Button isIconOnly variant="ghost" aria-label={t("Więcej", "More")}>
										<EllipsisVertical className="size-4" />
									</Button>
								</Dropdown.Trigger>
								<Dropdown.Popover placement="bottom end">
									<Dropdown.Menu
										onAction={(key) => {
											if (key === "edit") drawer.current?.edit(c);
											if (key === "financing") setOpen({ kind: "financing" });
											if (key === "delete") setConfirmDelete(true);
										}}
									>
										<Dropdown.Item id="edit" textValue={t("Edytuj dane", "Edit data")}>
											<Pencil className="size-4" />
											<Label>{t("Edytuj dane", "Edit data")}</Label>
										</Dropdown.Item>
										<Dropdown.Item id="financing" textValue={t("Finansowanie", "Financing")}>
											<Landmark className="size-4" />
											<Label>{t("Finansowanie", "Financing")}</Label>
										</Dropdown.Item>
										<Dropdown.Item id="delete" textValue={t("Usuń", "Delete")} variant="danger">
											<Trash2 className="size-4" />
											<Label>
												{t("Usuń (tylko nieprzekazywany)", "Delete (never handed over)")}
											</Label>
										</Dropdown.Item>
									</Dropdown.Menu>
								</Dropdown.Popover>
							</Dropdown>
						</div>
					) : null
				}
			/>
			<div className="grid gap-5 lg:grid-cols-[1fr_22rem]">
				<Card className="p-0">
					<Tabs
						selectedKey={tab}
						onSelectionChange={(k) =>
							void navigate({
								search: { tab: k === "data" ? undefined : (k as "handovers" | "history") },
								replace: true,
							})
						}
					>
						<Tabs.ListContainer className="border-b border-separator px-4 pt-3">
							<Tabs.List aria-label={t("Samochód", "Car")}>
								<Tabs.Tab id="data">
									{t("Dane", "Data")}
									<Tabs.Indicator />
								</Tabs.Tab>
								<Tabs.Tab id="handovers">
									{t(
										`Przekazania (${handovers.data?.length ?? 0})`,
										`Handovers (${handovers.data?.length ?? 0})`,
									)}
									<Tabs.Indicator />
								</Tabs.Tab>
								<Tabs.Tab id="history">
									{t(
										`Historia statusów (${history.data?.length ?? 0})`,
										`Status history (${history.data?.length ?? 0})`,
									)}
									<Tabs.Indicator />
								</Tabs.Tab>
							</Tabs.List>
						</Tabs.ListContainer>
						<Tabs.Panel id="data" className="p-5">
							<InfoList
								items={[
									{ label: t("Marka", "Make"), value: c.make ?? "—" },
									{ label: t("Rok produkcji", "Year"), value: c.productionYear ?? "—" },
									{
										label: t("Rejestracja", "Plate"),
										value: <span className="font-mono">{c.plate}</span>,
									},
									{ label: "VIN", value: <span className="font-mono">{c.vin ?? "—"}</span> },
									{ label: t("Spółka", "Company"), value: c.legalEntityName },
									{
										label: t("Przegląd do", "Inspection until"),
										value: <Due date={c.inspectionDue} />,
									},
									{ label: t("OC do", "Insurance until"), value: <Due date={c.insuranceDue} /> },
									{
										label: t("Finansowanie", "Financing"),
										value:
											c.financing === "LEASING"
												? `${t("Leasing", "Leasing")} · ${c.leasingName ?? ""} · ${date(c.leaseStart)} – ${date(c.leaseEnd)} (${c.leaseMonths} ${t("mies.", "mo.")})`
												: c.financing === "PAID"
													? `${t("Kupiony", "Bought")} ${date(c.purchaseDate)}`
													: t("Nieznane", "Unknown"),
									},
									...(c.financing === "LEASING" && manager
										? [
												{
													label: t("Rata", "Instalment"),
													value: <span className="figures">{money(c.instalment)}</span>,
												},
												{ label: t("Umowa", "Contract"), value: c.contractNo ?? "—" },
											]
										: []),
									{ label: t("Notatki", "Notes"), value: c.notes ?? "—" },
								]}
							/>
						</Tabs.Panel>
						<Tabs.Panel id="handovers">
							{(handovers.data ?? []).length === 0 ? (
								<EmptyState
									icon={CarFront}
									title={t("Jeszcze nie przekazywany", "Never handed over")}
								/>
							) : (
								<ul className="flex flex-col">
									{(handovers.data ?? []).map((h) => (
										<li
											key={h.id}
											className="flex items-start gap-3 border-b border-separator/60 px-5 py-3 last:border-b-0"
										>
											<UserAvatar name={h.holderName} />
											<div className="flex min-w-0 flex-1 flex-col gap-0.5">
												<span className="flex flex-wrap items-center gap-2">
													<span className="text-sm font-medium">{h.holderName}</span>
													<Chip size="sm" variant="soft" color={handoverStateColor(h.state)}>
														{handoverStateLabel(h.state, i18n)}
													</Chip>
												</span>
												<span className="text-xs text-muted">
													{date(h.issueDate)} –{" "}
													{h.returnedOn
														? date(h.returnedOn)
														: h.plannedReturn
															? `${date(h.plannedReturn)} ${t("(plan)", "(planned)")}`
															: t("bezterminowo", "open-ended")}
													{" · "}
													{h.issueMileage.toLocaleString(locale)} km
													{h.returnMileage != null
														? ` → ${h.returnMileage.toLocaleString(locale)} km`
														: ""}
													{" · "}
													{h.issueFuel}%{h.returnFuel != null ? ` → ${h.returnFuel}%` : ""}
												</span>
												{h.cancelReason ? (
													<span className="text-xs text-[var(--obs-danger)]">{h.cancelReason}</span>
												) : null}
												{h.notes ? <span className="text-xs text-muted">{h.notes}</span> : null}
											</div>
											{manager ? (
												<div className="flex shrink-0 gap-1">
													{h.state === "CURRENT" ||
													h.state === "OVERDUE" ||
													h.state === "PLANNED" ? (
														<>
															<Button
																size="sm"
																variant="ghost"
																onPress={() => setOpen({ kind: "change", handover: h })}
															>
																{t("Zmień", "Change")}
															</Button>
															<Button
																size="sm"
																variant="ghost"
																onPress={() => setOpen({ kind: "cancel", handover: h })}
															>
																{t("Anuluj", "Cancel")}
															</Button>
														</>
													) : null}
													{h.state === "RETURNED" &&
													h.returnedOn ===
														new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Warsaw" }).format(
															new Date(),
														) ? (
														<Button
															size="sm"
															variant="ghost"
															isPending={undo.isPending}
															onPress={() =>
																undo.mutate(
																	{ id: h.id, rowVersion: h.rowVersion },
																	{ onError: (e) => toast.danger(problemText(e, i18n)) },
																)
															}
														>
															<Undo2 className="size-4" />
															{t("Cofnij zwrot", "Undo return")}
														</Button>
													) : null}
												</div>
											) : null}
										</li>
									))}
								</ul>
							)}
						</Tabs.Panel>
						<Tabs.Panel id="history">
							<ul className="flex flex-col">
								{(history.data ?? []).map((s) => (
									<li
										key={s.id}
										className="flex flex-col gap-0.5 border-b border-separator/60 px-5 py-3 last:border-b-0"
									>
										<span className="text-sm font-medium">
											{i18n.lang === "pl" ? s.statusNamePl : s.statusNameEn}
											{s.repairShop ? (
												<span className="font-normal text-muted"> · {s.repairShop}</span>
											) : null}
										</span>
										<span className="text-xs text-muted">
											{t("od", "from")} {date(s.effectiveOn)} · {s.changedByName}
											{s.note ? ` · ${s.note}` : ""}
										</span>
									</li>
								))}
							</ul>
						</Tabs.Panel>
					</Tabs>
				</Card>
				<Card className="self-start">
					<Card.Content className="flex flex-col gap-4">
						<div className="flex flex-wrap gap-2">
							<Chip
								variant="soft"
								color={availabilityColor[c.availability as Availability] ?? "default"}
							>
								{availabilityLabel(c.availability, i18n)}
							</Chip>
							<Chip variant="soft">{statusName(c, i18n)}</Chip>
						</div>
						{c.repairShopName ? (
							<p className="text-sm">
								<span className="text-muted">{t("Warsztat: ", "Repair shop: ")}</span>
								{c.repairShopName}
							</p>
						) : null}
						<div className="flex flex-col gap-1">
							<span className="font-mono text-[11px] tracking-[0.08em] text-muted uppercase">
								{c.holderPlanned ? t("Następny", "Next") : t("Kto ma", "Who has it")}
							</span>
							{c.holderName ? (
								<span className="flex items-center gap-2">
									<UserAvatar name={c.holderName} />
									<span className="flex flex-col">
										<span className="text-sm font-medium">{c.holderName}</span>
										<span className="text-xs text-muted">
											{date(c.holderFrom)} –{" "}
											{c.holderUntil ? date(c.holderUntil) : t("bezterminowo", "open-ended")}
										</span>
									</span>
								</span>
							) : (
								<span className="text-sm text-muted">
									{t("Nikt - samochód wolny", "Nobody - the car is free")}
								</span>
							)}
						</div>
						<p className="text-xs text-muted">
							{t("Status od", "Status since")} {date(c.statusSince)}
						</p>
					</Card.Content>
				</Card>
			</div>
			{open?.kind === "status" ? <StatusDialog car={c} onClose={() => setOpen(null)} /> : null}
			{open?.kind === "financing" ? (
				<FinancingDialog car={c} onClose={() => setOpen(null)} />
			) : null}
			{open?.kind === "handover" ? <HandoverDialog car={c} onClose={() => setOpen(null)} /> : null}
			{open?.kind === "return" ? (
				<ReturnDialog handover={open.handover} onClose={() => setOpen(null)} />
			) : null}
			{open?.kind === "change" ? (
				<ChangeHandoverDialog handover={open.handover} onClose={() => setOpen(null)} />
			) : null}
			{open?.kind === "cancel" ? (
				<CancelHandoverDialog handover={open.handover} onClose={() => setOpen(null)} />
			) : null}
			<ConfirmDialog
				isOpen={confirmDelete}
				title={t("Usunąć samochód?", "Delete the car?")}
				description={t(
					"Tylko samochód nigdy nieprzekazany; inny przenieś do archiwum.",
					"Only a car never handed over; archive any other.",
				)}
				confirmLabel={t("Usuń", "Delete")}
				isPending={remove.isPending}
				error={remove.error}
				onConfirm={() => remove.mutate({ id: c.id, rowVersion: c.rowVersion })}
				onClose={() => setConfirmDelete(false)}
			/>
			<CarDrawer ref={drawer} />
		</>
	);
}
