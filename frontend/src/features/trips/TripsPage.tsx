import { Button, Card, Chip, Table, ToggleButton, ToggleButtonGroup } from "@heroui/react";
import { useInfiniteQuery } from "@tanstack/react-query";
import { getRouteApi, useNavigate } from "@tanstack/react-router";
import { Plane, Plus } from "lucide-react";
import { useRef } from "react";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError, EmptyState, LoadMore, SelectFilter, TableSkeleton } from "#/components/ui";
import { useMe } from "#/features/auth/session";
import { useOnDemandTotal } from "#/hooks/useOnDemandTotal";
import { useI18n } from "#/i18n";
import { tripsCountQuery, tripsQuery } from "./hooks";
import { TripDrawer, type TripDrawerCommand } from "./TripDrawer";
import {
	money,
	PURPOSE_ICONS,
	PURPOSES,
	type Purpose,
	purposeLabel,
	statusColor,
	statusLabel,
	TRIP_STATUSES,
	type TripStatus,
	target,
} from "./types";

const route = getRouteApi("/_app/trips/");

/**
 * Business trips (ADR-0019): my own, the ones waiting for my approval, or everybody's (managers). Each row shows what
 * the trip is for, where and when, how far its settlement got and what is left to pay.
 */
export function TripsPage() {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const me = useMe();
	const manager = me.role === "ADMIN" || me.role === "MANAGER";
	const search = route.useSearch();
	const navigate = route.useNavigate();
	const goTo = useNavigate();
	const drawer = useRef<TripDrawerCommand>(null);
	const scope = manager ? (search.scope ?? "MINE") : "MINE";
	const filters = { scope, status: search.status, purpose: search.purpose };
	const query = useInfiniteQuery(tripsQuery(filters));
	const total = useOnDemandTotal(tripsCountQuery(filters));
	const trips = query.data?.pages.flatMap((p) => p.items) ?? [];
	const when = (iso: string) =>
		new Intl.DateTimeFormat(locale, {
			day: "numeric",
			month: "short",
			hour: "2-digit",
			minute: "2-digit",
			timeZone: "Europe/Warsaw",
		}).format(new Date(iso));

	return (
		<>
			<PageHeader
				eyebrow={t("Organizacja", "Organization")}
				title={t("Delegacje", "Business trips")}
				description={t(
					"Wyjazdy do klientów, na targi i na projekty - i ich rozliczenie: diety, ryczałty, kilometrówka i wydatki.",
					"Trips to clients, trade fairs and project sites - and their settlement: per diems, lump sums, mileage and expenses.",
				)}
				actions={
					<Button onPress={() => drawer.current?.create()}>
						<Plus className="size-4" />
						{t("Nowa delegacja", "New trip")}
					</Button>
				}
			/>
			<Card className="overflow-hidden p-0">
				<div className="flex flex-col flex-wrap gap-3 border-b border-separator p-4 sm:flex-row sm:items-center">
					{manager ? (
						<ToggleButtonGroup
							aria-label={t("Czyje", "Whose")}
							selectionMode="single"
							disallowEmptySelection
							size="sm"
							selectedKeys={new Set([scope])}
							onSelectionChange={(keys) => {
								const next = [...keys][0] as "MINE" | "TO_APPROVE" | "ALL";
								void navigate({
									search: (s) => ({ ...s, scope: next === "MINE" ? undefined : next }),
									replace: true,
								});
							}}
						>
							<ToggleButton id="MINE">{t("Moje", "Mine")}</ToggleButton>
							<ToggleButton id="TO_APPROVE">{t("Do akceptacji", "To approve")}</ToggleButton>
							<ToggleButton id="ALL">{t("Wszystkie", "All")}</ToggleButton>
						</ToggleButtonGroup>
					) : null}
					<SelectFilter
						label={t("Status", "Status")}
						className="w-full sm:w-52"
						value={search.status}
						options={TRIP_STATUSES.map((s) => ({ id: s, label: statusLabel(s, i18n) }))}
						onChange={(status) =>
							void navigate({
								search: (s) => ({ ...s, status: status as TripStatus | undefined }),
								replace: true,
							})
						}
					/>
					<SelectFilter
						label={t("Cel", "Purpose")}
						className="w-full sm:w-60"
						value={search.purpose}
						options={PURPOSES.map((p) => ({ id: p, label: purposeLabel(p, i18n) }))}
						onChange={(purpose) =>
							void navigate({
								search: (s) => ({ ...s, purpose: purpose as Purpose | undefined }),
								replace: true,
							})
						}
					/>
				</div>
				{query.isPending ? (
					<TableSkeleton />
				) : query.isError ? (
					<div className="p-4">
						<ApiError error={query.error} />
					</div>
				) : trips.length === 0 ? (
					<EmptyState icon={Plane} title={t("Brak delegacji", "No trips")} />
				) : (
					<>
						<Table className="rounded-none shadow-none">
							<Table.ScrollContainer>
								<Table.Content
									aria-label={t("Delegacje", "Business trips")}
									className="min-w-[1100px]"
								>
									<Table.Header>
										<Table.Column isRowHeader>{t("Delegacja", "Trip")}</Table.Column>
										{scope !== "MINE" ? <Table.Column>{t("Kto", "Who")}</Table.Column> : null}
										<Table.Column>{t("Cel", "Purpose")}</Table.Column>
										<Table.Column>{t("Dokąd", "Where")}</Table.Column>
										<Table.Column>{t("Kiedy", "When")}</Table.Column>
										<Table.Column>{t("Status", "Status")}</Table.Column>
										<Table.Column className="text-right">{t("Razem", "Total")}</Table.Column>
										<Table.Column className="text-right">{t("Do wypłaty", "To pay")}</Table.Column>
									</Table.Header>
									<Table.Body>
										{trips.map((trip) => {
											const Icon = PURPOSE_ICONS[trip.purpose as Purpose] ?? PURPOSE_ICONS.OTHER;
											return (
												<Table.Row
													key={trip.id}
													id={trip.id}
													className="is-clickable"
													onAction={() =>
														void goTo({ to: "/trips/$tripId", params: { tripId: trip.id } })
													}
												>
													<Table.Cell>
														<span className="font-mono text-xs">{trip.number}</span>
													</Table.Cell>
													{scope !== "MINE" ? (
														<Table.Cell>
															<div className="flex flex-col">
																<span className="text-sm">{trip.travellerName}</span>
																<span className="text-xs text-muted">
																	{trip.travellerDepartment ?? ""}
																</span>
															</div>
														</Table.Cell>
													) : null}
													<Table.Cell>
														<div className="flex items-start gap-2">
															<Icon className="mt-0.5 size-4 shrink-0 text-[var(--obs-champagne)]" />
															<div className="flex min-w-0 flex-col">
																<span className="truncate text-sm font-medium text-foreground">
																	{target(trip)}
																</span>
																<span className="text-xs text-muted">
																	{purposeLabel(trip.purpose, i18n)}
																</span>
															</div>
														</div>
													</Table.Cell>
													<Table.Cell>
														<span className="text-sm">
															{trip.destination}
															{trip.country !== "PL" ? (
																<span className="text-muted"> · {trip.country}</span>
															) : null}
														</span>
													</Table.Cell>
													<Table.Cell>
														<span className="text-xs tabular-nums">
															{when(trip.startsAt)} – {when(trip.endsAt)}
														</span>
													</Table.Cell>
													<Table.Cell>
														<Chip
															size="sm"
															variant="soft"
															color={statusColor[trip.status as TripStatus] ?? "default"}
														>
															{statusLabel(trip.status, i18n)}
														</Chip>
													</Table.Cell>
													<Table.Cell className="text-right">
														<span className="figures text-xs">
															{money(trip.total, trip.currency, locale)}
														</span>
													</Table.Cell>
													<Table.Cell className="text-right">
														<span
															className={`figures text-xs ${Number(trip.toPay) < 0 ? "text-[var(--obs-danger)]" : ""}`}
														>
															{money(trip.toPay, trip.currency, locale)}
														</span>
													</Table.Cell>
												</Table.Row>
											);
										})}
									</Table.Body>
								</Table.Content>
							</Table.ScrollContainer>
						</Table>
						<LoadMore
							noun={t("delegacji", "trips")}
							shown={trips.length}
							hasMore={query.hasNextPage}
							isLoading={query.isFetchingNextPage}
							onLoadMore={() => void query.fetchNextPage()}
							total={total}
						/>
					</>
				)}
			</Card>
			<TripDrawer ref={drawer} />
		</>
	);
}
