import { Button, Card, Chip, Label, SearchField, Switch, Table } from "@heroui/react";
import { useInfiniteQuery, useQuery } from "@tanstack/react-query";
import { getRouteApi, useNavigate } from "@tanstack/react-router";
import { CarFront, Plus, Wrench } from "lucide-react";
import { useRef, useState } from "react";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError, EmptyState, LoadMore, SelectFilter, TableSkeleton } from "#/components/ui";
import { useMe } from "#/features/auth/session";
import { legalEntitiesQuery } from "#/features/companies/hooks";
import { useDebouncedValue } from "#/hooks/useDebouncedValue";
import { useOnDemandTotal } from "#/hooks/useOnDemandTotal";
import { useI18n } from "#/i18n";
import { CarDrawer, type CarDrawerCommand } from "./CarDrawer";
import { carStatusesQuery, carsCountQuery, carsQuery, partnersQuery } from "./hooks";
import { type PartnersCommand, PartnersDialog } from "./PartnersDialog";
import {
	AVAILABILITY,
	type Availability,
	availabilityColor,
	availabilityLabel,
	canManageFleet,
	dueSoon,
	statusName,
} from "./types";

const route = getRouteApi("/_app/fleet/");

/**
 * The fleet (ADR-0018): every car with its status, today's availability and who has it, filters in the URL, the total
 * on request. Managers add cars and keep the lists of repair shops and leasing companies.
 */
export function FleetPage() {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const me = useMe();
	const manager = canManageFleet(me.role);
	const search = route.useSearch();
	const navigate = route.useNavigate();
	const goTo = useNavigate();
	const drawer = useRef<CarDrawerCommand>(null);
	const partnersDialog = useRef<PartnersCommand>(null);
	const statuses = useQuery(carStatusesQuery());
	const entities = useQuery(legalEntitiesQuery());
	const shops = useQuery(partnersQuery("REPAIR_SHOP"));
	const [text, setText] = useState(search.q ?? "");
	const q = useDebouncedValue(text.trim(), 300);
	if ((search.q ?? "") !== q)
		void navigate({ search: (s) => ({ ...s, q: q || undefined }), replace: true });

	const filters = {
		search: search.q,
		status: search.status,
		availability: search.availability,
		legalEntityId: search.company,
		repairShopId: search.shop,
		archived: search.archived,
		dueSoon: search.due,
	};
	const query = useInfiniteQuery(carsQuery(filters));
	const total = useOnDemandTotal(carsCountQuery(filters));
	const cars = query.data?.pages.flatMap((p) => p.items) ?? [];
	const date = (iso: string) =>
		new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(new Date(`${iso}T00:00:00`));
	const set = (patch: Record<string, unknown>) =>
		void navigate({ search: (s) => ({ ...s, ...patch }), replace: true });

	return (
		<>
			<PageHeader
				eyebrow={t("Organizacja", "Organization")}
				title={t("Flota", "Fleet")}
				description={t(
					"Samochody spółek: status, finansowanie, terminy przeglądu i OC oraz kto ma który samochód.",
					"The companies' cars: status, financing, inspection and insurance deadlines, and who has which car.",
				)}
				actions={
					manager ? (
						<div className="flex gap-2">
							<Button variant="secondary" onPress={() => partnersDialog.current?.open()}>
								<Wrench className="size-4" />
								{t("Warsztaty i leasing", "Repair shops & leasing")}
							</Button>
							<Button onPress={() => drawer.current?.create()}>
								<Plus className="size-4" />
								{t("Nowy samochód", "New car")}
							</Button>
						</div>
					) : null
				}
			/>
			<Card className="overflow-hidden p-0">
				<div className="flex flex-col flex-wrap gap-3 border-b border-separator p-4 lg:flex-row lg:items-center">
					<SearchField
						aria-label={t("Szukaj samochodu", "Search cars")}
						className="w-full lg:max-w-xs"
						value={text}
						onChange={setText}
					>
						<SearchField.Group>
							<SearchField.SearchIcon />
							<SearchField.Input
								placeholder={t("Nazwa, rejestracja, marka…", "Name, plate, make…")}
							/>
							<SearchField.ClearButton />
						</SearchField.Group>
					</SearchField>
					<SelectFilter
						label={t("Status", "Status")}
						className="w-full sm:w-56"
						value={search.status}
						options={(statuses.data ?? []).map((s) => ({
							id: s.status,
							label: i18n.lang === "pl" ? s.namePl : s.nameEn,
						}))}
						onChange={(status) => set({ status })}
					/>
					<SelectFilter
						label={t("Dostępność", "Availability")}
						className="w-full sm:w-56"
						value={search.availability}
						options={AVAILABILITY.map((a) => ({ id: a, label: availabilityLabel(a, i18n) }))}
						onChange={(availability) =>
							set({ availability: availability as Availability | undefined })
						}
					/>
					<SelectFilter
						label={t("Spółka", "Company")}
						className="w-full sm:w-56"
						value={search.company ? String(search.company) : undefined}
						options={(entities.data ?? []).map((e) => ({ id: String(e.id), label: e.name }))}
						onChange={(company) => set({ company: company ? Number(company) : undefined })}
					/>
					<SelectFilter
						label={t("Warsztat", "Repair shop")}
						className="w-full sm:w-60"
						value={search.shop ? String(search.shop) : undefined}
						options={(shops.data ?? []).map((p) => ({ id: String(p.id), label: p.name }))}
						onChange={(shop) => set({ shop: shop ? Number(shop) : undefined })}
					/>
					<div className="flex flex-wrap gap-4 lg:ml-auto">
						<Switch isSelected={Boolean(search.due)} onChange={(v) => set({ due: v || undefined })}>
							<Switch.Control>
								<Switch.Thumb />
							</Switch.Control>
							<Switch.Content>
								<Label>{t("Przegląd / OC w 30 dni", "Inspection / insurance in 30 days")}</Label>
							</Switch.Content>
						</Switch>
						<Switch
							isSelected={Boolean(search.archived)}
							onChange={(v) => set({ archived: v || undefined })}
						>
							<Switch.Control>
								<Switch.Thumb />
							</Switch.Control>
							<Switch.Content>
								<Label>{t("Pokaż archiwum", "Show archived")}</Label>
							</Switch.Content>
						</Switch>
					</div>
				</div>
				{query.isPending ? (
					<TableSkeleton />
				) : query.isError ? (
					<div className="p-4">
						<ApiError error={query.error} />
					</div>
				) : cars.length === 0 ? (
					<EmptyState icon={CarFront} title={t("Brak samochodów", "No cars")} />
				) : (
					<>
						<Table className="rounded-none shadow-none">
							<Table.ScrollContainer>
								<Table.Content aria-label={t("Flota", "Fleet")} className="min-w-[1100px]">
									<Table.Header>
										<Table.Column isRowHeader>{t("Samochód", "Car")}</Table.Column>
										<Table.Column>{t("Status", "Status")}</Table.Column>
										<Table.Column>{t("Dostępność", "Availability")}</Table.Column>
										<Table.Column>{t("Kto ma", "Holder")}</Table.Column>
										<Table.Column>{t("Spółka", "Company")}</Table.Column>
										<Table.Column>{t("Przegląd", "Inspection")}</Table.Column>
										<Table.Column>OC</Table.Column>
										<Table.Column className="text-right">{t("Rok", "Year")}</Table.Column>
									</Table.Header>
									<Table.Body>
										{cars.map((c) => (
											<Table.Row
												key={c.id}
												id={c.id}
												className="is-clickable"
												onAction={() => void goTo({ to: "/fleet/$carId", params: { carId: c.id } })}
											>
												<Table.Cell>
													<div className="flex flex-col">
														<span className="font-medium text-foreground">{c.name}</span>
														<span className="font-mono text-[11px] tracking-wider text-muted">
															{c.plate}
														</span>
													</div>
												</Table.Cell>
												<Table.Cell>
													<div className="flex flex-col">
														<span className="text-sm">{statusName(c, i18n)}</span>
														{c.repairShopName ? (
															<span className="text-xs text-muted">{c.repairShopName}</span>
														) : null}
													</div>
												</Table.Cell>
												<Table.Cell>
													<Chip
														size="sm"
														variant="soft"
														color={availabilityColor[c.availability as Availability] ?? "default"}
													>
														{availabilityLabel(c.availability, i18n)}
													</Chip>
												</Table.Cell>
												<Table.Cell>
													{c.holderName ? (
														<div className="flex flex-col text-xs">
															<span className="text-sm text-foreground">{c.holderName}</span>
															<span className="text-muted">
																{c.holderPlanned
																	? `${t("od", "from")} ${date(c.holderFrom ?? "")} · `
																	: ""}
																{c.holderUntil
																	? `${t("do", "until")} ${date(c.holderUntil)}`
																	: t("bezterminowo", "open-ended")}
															</span>
														</div>
													) : (
														<span className="text-xs text-muted">—</span>
													)}
												</Table.Cell>
												<Table.Cell>
													<span className="text-xs">{c.legalEntityName}</span>
												</Table.Cell>
												<Table.Cell>
													<Due date={c.inspectionDue} />
												</Table.Cell>
												<Table.Cell>
													<Due date={c.insuranceDue} />
												</Table.Cell>
												<Table.Cell className="text-right">
													<span className="figures text-xs">{c.productionYear ?? ""}</span>
												</Table.Cell>
											</Table.Row>
										))}
									</Table.Body>
								</Table.Content>
							</Table.ScrollContainer>
						</Table>
						<LoadMore
							noun={t("samochodów", "cars")}
							shown={cars.length}
							hasMore={query.hasNextPage}
							isLoading={query.isFetchingNextPage}
							onLoadMore={() => void query.fetchNextPage()}
							total={total}
						/>
					</>
				)}
			</Card>
			<CarDrawer ref={drawer} />
			<PartnersDialog ref={partnersDialog} />
		</>
	);
}

/** A deadline, red when past, amber within 30 days. */
export function Due({ date }: { date: string | null | undefined }) {
	const { locale } = useI18n();
	if (!date) return <span className="text-xs text-muted">—</span>;
	const state = dueSoon(date);
	return (
		<span
			className={`text-xs tabular-nums ${state === "past" ? "font-semibold text-[var(--obs-danger)]" : state === "soon" ? "font-medium text-[var(--obs-warning)]" : "text-muted"}`}
		>
			{new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(
				new Date(`${date}T00:00:00`),
			)}
		</span>
	);
}
