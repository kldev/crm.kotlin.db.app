import { Button, Card, Chip, SearchField, Table } from "@heroui/react";
import { useInfiniteQuery, useQuery } from "@tanstack/react-query";
import { getRouteApi, useNavigate } from "@tanstack/react-router";
import { FileText, Plus } from "lucide-react";
import { useRef, useState } from "react";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError, EmptyState, LoadMore, SelectFilter, TableSkeleton } from "#/components/ui";
import { legalEntitiesQuery } from "#/features/companies/hooks";
import { useDebouncedValue } from "#/hooks/useDebouncedValue";
import { useOnDemandTotal } from "#/hooks/useOnDemandTotal";
import { useI18n } from "#/i18n";
import { offersCountQuery, offersQuery, offerTemplatesQuery } from "./hooks";
import { type NewOfferCommand, NewOfferDialog } from "./NewOfferDialog";
import {
	money,
	OFFER_STATUSES,
	type OfferStatus,
	offerStatusColor,
	offerStatusLabel,
	templateName,
} from "./types";

const route = getRouteApi("/_app/offers/");

/** Offers, newest first; filters in the URL, the total on request. */
export function OffersPage() {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const search = route.useSearch();
	const navigate = route.useNavigate();
	const goTo = useNavigate();
	const dialog = useRef<NewOfferCommand>(null);
	const templates = useQuery(offerTemplatesQuery());
	const [text, setText] = useState(search.q ?? "");
	const q = useDebouncedValue(text.trim(), 300);
	if ((search.q ?? "") !== q)
		void navigate({ search: (s) => ({ ...s, q: q || undefined }), replace: true });

	const entities = useQuery(legalEntitiesQuery());
	const filters = {
		status: search.status,
		templateKey: search.template,
		search: search.q,
		legalEntityId: search.company,
	};
	const query = useInfiniteQuery(offersQuery(filters));
	const total = useOnDemandTotal(offersCountQuery(filters));
	const offers = query.data?.pages.flatMap((p) => p.items) ?? [];
	const date = (iso: string) =>
		new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(new Date(`${iso}T00:00:00`));

	return (
		<>
			<PageHeader
				eyebrow="CRM"
				title={t("Oferty", "Offers")}
				description={t(
					"Oferty dla klientów z szablonów Sales Budownictwo, Sales IT i Sales Outsourcing, z PDF w motywie Obsidian.",
					"Offers for clients from the Sales Construction, Sales IT and Sales Outsourcing templates, with an Obsidian PDF.",
				)}
				actions={
					<Button onPress={() => dialog.current?.open()}>
						<Plus className="size-4" />
						{t("Nowa oferta", "New offer")}
					</Button>
				}
			/>
			<Card className="overflow-hidden p-0">
				<div className="flex flex-col gap-3 border-b border-separator p-4 sm:flex-row sm:items-center">
					<SearchField
						aria-label={t("Szukaj ofert", "Search offers")}
						className="w-full sm:max-w-xs"
						value={text}
						onChange={setText}
					>
						<SearchField.Group>
							<SearchField.SearchIcon />
							<SearchField.Input placeholder={t("Numer albo tytuł…", "Number or title…")} />
							<SearchField.ClearButton />
						</SearchField.Group>
					</SearchField>
					<SelectFilter
						label={t("Status", "Status")}
						value={search.status}
						options={OFFER_STATUSES.map((s) => ({ id: s, label: offerStatusLabel(s, i18n) }))}
						onChange={(status) =>
							void navigate({
								search: (s) => ({ ...s, status: status as OfferStatus | undefined }),
							})
						}
					/>
					<SelectFilter
						label={t("Szablon", "Template")}
						className="w-full sm:w-56"
						value={search.template}
						options={(templates.data ?? []).map((tpl) => ({
							id: tpl.key,
							label: templateName(tpl, i18n),
						}))}
						onChange={(template) => void navigate({ search: (s) => ({ ...s, template }) })}
					/>
					<SelectFilter
						label={t("Spółka", "Company")}
						className="w-full sm:w-56"
						value={search.company ? String(search.company) : undefined}
						options={(entities.data ?? []).map((e) => ({ id: String(e.id), label: e.name }))}
						onChange={(company) =>
							void navigate({
								search: (s) => ({ ...s, company: company ? Number(company) : undefined }),
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
				) : offers.length === 0 ? (
					<EmptyState
						icon={FileText}
						title={t("Brak ofert", "No offers")}
						description={t(
							"Utwórz pierwszą ofertę dla klienta.",
							"Create the first offer for a client.",
						)}
					/>
				) : (
					<>
						<Table className="rounded-none shadow-none">
							<Table.ScrollContainer>
								<Table.Content aria-label={t("Oferty", "Offers")} className="min-w-[900px]">
									<Table.Header>
										<Table.Column isRowHeader>{t("Oferta", "Offer")}</Table.Column>
										<Table.Column>{t("Klient", "Client")}</Table.Column>
										<Table.Column>{t("Szablon", "Template")}</Table.Column>
										<Table.Column>{t("Spółka", "Company")}</Table.Column>
										<Table.Column>{t("Status", "Status")}</Table.Column>
										<Table.Column>{t("Ważna do", "Valid until")}</Table.Column>
										<Table.Column className="text-right">{t("Brutto", "Gross")}</Table.Column>
									</Table.Header>
									<Table.Body>
										{offers.map((o) => (
											<Table.Row
												key={o.id}
												id={o.id}
												className="is-clickable"
												onAction={() =>
													void goTo({ to: "/offers/$offerId", params: { offerId: o.id } })
												}
											>
												<Table.Cell>
													<div className="flex flex-col">
														<span className="font-medium text-foreground">{o.title}</span>
														<span className="font-mono text-[11px] text-muted">
															{o.number} · {o.authorName}
														</span>
													</div>
												</Table.Cell>
												<Table.Cell>{o.clientName}</Table.Cell>
												<Table.Cell>{templateName(o, i18n)}</Table.Cell>
												<Table.Cell>
													<span className="text-xs">{o.legalEntityName}</span>
												</Table.Cell>
												<Table.Cell>
													<Chip
														size="sm"
														variant="soft"
														className="whitespace-nowrap"
														color={offerStatusColor[o.status as OfferStatus] ?? "default"}
													>
														{offerStatusLabel(o.status, i18n)}
													</Chip>
												</Table.Cell>
												<Table.Cell>
													<span className="text-xs">{date(o.validUntil)}</span>
												</Table.Cell>
												<Table.Cell className="figures text-right whitespace-nowrap">
													{money(o.totalGross, o.currency, locale)}
												</Table.Cell>
											</Table.Row>
										))}
									</Table.Body>
								</Table.Content>
							</Table.ScrollContainer>
						</Table>
						<LoadMore
							noun={t("ofert", "offers")}
							shown={offers.length}
							hasMore={query.hasNextPage}
							isLoading={query.isFetchingNextPage}
							onLoadMore={() => void query.fetchNextPage()}
							total={total}
						/>
					</>
				)}
			</Card>
			<NewOfferDialog
				ref={dialog}
				onCreated={(o) => void goTo({ to: "/offers/$offerId", params: { offerId: o.id } })}
			/>
		</>
	);
}
