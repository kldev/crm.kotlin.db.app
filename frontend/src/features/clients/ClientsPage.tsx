import { Button, Card, SearchField, Table, toast } from "@heroui/react";
import { useInfiniteQuery } from "@tanstack/react-query";
import { getRouteApi, useNavigate } from "@tanstack/react-router";
import { Building2, Plus } from "lucide-react";
import { useRef, useState } from "react";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError, EmptyState, LoadMore, SelectFilter, TableSkeleton } from "#/components/ui";
import { CITIES, CLIENT_STATUSES, clientStatusLabel } from "#/features/types";
import { useDebouncedValue } from "#/hooks/useDebouncedValue";
import { useOnDemandTotal } from "#/hooks/useOnDemandTotal";
import { useI18n } from "#/i18n";
import { formatRelative } from "#/lib";
import { type ClientFormCommand, ClientFormDrawer } from "./ClientFormDrawer";
import { ClientStatusChip } from "./ClientStatusChip";
import { clientsCountQuery, clientsQuery } from "./hooks";

const route = getRouteApi("/_app/clients/");

export function ClientsPage() {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const search = route.useSearch();
	const navigate = route.useNavigate();
	const goTo = useNavigate();
	const drawer = useRef<ClientFormCommand>(null);

	// The text box is local while typing; the URL (and the query) follow 300 ms later.
	const [text, setText] = useState(search.q ?? "");
	const prefix = useDebouncedValue(text.trim(), 300);
	if ((search.q ?? "") !== prefix) {
		void navigate({ search: (s) => ({ ...s, q: prefix || undefined }), replace: true });
	}

	const filters = { namePrefix: search.q, city: search.city, status: search.status };
	const query = useInfiniteQuery(clientsQuery(filters));
	const total = useOnDemandTotal(clientsCountQuery(filters));
	const clients = query.data?.pages.flatMap((p) => p.items) ?? [];
	const filtered = Boolean(search.q || search.city || search.status);

	return (
		<>
			<PageHeader
				eyebrow={t("Kartoteka", "Directory")}
				title={t("Klienci", "Clients")}
				description={
					search.q
						? t("Pasujące nazwy, alfabetycznie.", "Matching names, in alphabetical order.")
						: t(
								"Najnowsi na górze. Wpisz początek nazwy, aby szukać wśród wszystkich klientów.",
								"Newest first. Type the beginning of a name to search all clients.",
							)
				}
				actions={
					<Button onPress={() => drawer.current?.create()}>
						<Plus className="size-4" />
						{t("Nowy klient", "New client")}
					</Button>
				}
			/>

			<Card className="overflow-hidden p-0">
				<div className="flex flex-col gap-3 border-b border-separator p-4 sm:flex-row sm:items-center">
					<SearchField
						aria-label={t("Szukaj klientów", "Search clients")}
						className="w-full sm:max-w-xs"
						value={text}
						onChange={setText}
					>
						<SearchField.Group>
							<SearchField.SearchIcon />
							<SearchField.Input placeholder={t("Nazwa zaczyna się od…", "Name starts with…")} />
							<SearchField.ClearButton />
						</SearchField.Group>
					</SearchField>
					<SelectFilter
						label={t("Miasto", "City")}
						value={search.city}
						options={CITIES.map((c) => ({ id: c, label: c }))}
						onChange={(city) => void navigate({ search: (s) => ({ ...s, city }) })}
					/>
					<SelectFilter
						label={t("Status", "Status")}
						value={search.status}
						options={CLIENT_STATUSES.map((s) => ({ id: s, label: clientStatusLabel(s, i18n) }))}
						onChange={(status) =>
							void navigate({
								search: (s) => ({
									...s,
									status: status as (typeof CLIENT_STATUSES)[number] | undefined,
								}),
							})
						}
					/>
				</div>

				{query.isPending ? (
					<TableSkeleton />
				) : query.isError ? (
					<div className="p-4">
						<ApiError
							error={query.error}
							title={t("Nie udało się wczytać klientów", "Clients could not be loaded")}
						/>
					</div>
				) : clients.length === 0 ? (
					<EmptyState
						icon={Building2}
						title={
							filtered
								? t("Brak pasujących klientów", "No clients match")
								: t("Nie ma jeszcze klientów", "No clients yet")
						}
						description={
							filtered
								? t(
										"Spróbuj krótszej nazwy albo wyczyść filtr.",
										"Try a shorter name or clear a filter.",
									)
								: t(
										"Dodaj pierwszego klienta, aby zacząć.",
										"Create the first client to get started.",
									)
						}
					/>
				) : (
					<>
						<Table className="rounded-none shadow-none">
							<Table.ScrollContainer>
								<Table.Content aria-label={t("Klienci", "Clients")} className="min-w-[760px]">
									<Table.Header>
										<Table.Column isRowHeader>{t("Klient", "Client")}</Table.Column>
										<Table.Column>NIP</Table.Column>
										<Table.Column>{t("Miasto", "City")}</Table.Column>
										<Table.Column>{t("Status", "Status")}</Table.Column>
										<Table.Column>{t("Opiekun", "Owner")}</Table.Column>
										<Table.Column>{t("Zmieniono", "Updated")}</Table.Column>
									</Table.Header>
									<Table.Body>
										{clients.map((c) => (
											<Table.Row
												key={c.id}
												id={c.id}
												className="is-clickable"
												onAction={() =>
													void goTo({ to: "/clients/$clientId", params: { clientId: c.id } })
												}
											>
												<Table.Cell>
													<div className="flex flex-col">
														<span className="font-medium text-foreground">{c.name}</span>
														<span className="text-xs text-muted">{c.email ?? "—"}</span>
													</div>
												</Table.Cell>
												<Table.Cell>
													<span className="figures text-xs">{c.nip ?? "—"}</span>
												</Table.Cell>
												<Table.Cell>{c.city ?? "—"}</Table.Cell>
												<Table.Cell>
													<ClientStatusChip status={c.status} />
												</Table.Cell>
												<Table.Cell>
													<span className="font-mono text-xs text-muted">
														{c.assignedUserLogin ?? t("nieprzypisany", "unassigned")}
													</span>
												</Table.Cell>
												<Table.Cell>
													<span className="text-xs text-muted">
														{formatRelative(c.updatedAt, locale)}
													</span>
												</Table.Cell>
											</Table.Row>
										))}
									</Table.Body>
								</Table.Content>
							</Table.ScrollContainer>
						</Table>
						<LoadMore
							noun={t("klientów", "clients")}
							shown={clients.length}
							hasMore={query.hasNextPage}
							isLoading={query.isFetchingNextPage}
							onLoadMore={() => void query.fetchNextPage()}
							total={total}
						/>
					</>
				)}
			</Card>

			<ClientFormDrawer
				ref={drawer}
				onSaved={(client) => {
					toast.success(t(`Dodano klienta „${client.name}”`, `Client "${client.name}" created`));
					void goTo({ to: "/clients/$clientId", params: { clientId: client.id } });
				}}
			/>
		</>
	);
}
