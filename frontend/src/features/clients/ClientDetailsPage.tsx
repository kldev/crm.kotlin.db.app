import { Button, Card, Skeleton, toast } from "@heroui/react";
import { useInfiniteQuery, useQuery } from "@tanstack/react-query";
import { getRouteApi, Link, useNavigate } from "@tanstack/react-router";
import {
	ArrowLeft,
	BriefcaseBusiness,
	Mail,
	MapPin,
	Pencil,
	Phone,
	Plus,
	Trash2,
} from "lucide-react";
import { useRef, useState } from "react";
import { PageHeader } from "#/components/layout/AppLayout";
import {
	ApiError,
	ConfirmDialog,
	EmptyState,
	InfoList,
	LoadMore,
	TableSkeleton,
} from "#/components/ui";
import { can, useMe } from "#/features/auth/session";
import { ClientOffers } from "#/features/offers/ClientOffers";
import { type NewOfferCommand, NewOfferDialog } from "#/features/offers/NewOfferDialog";
import { projectsCountQuery, projectsQuery } from "#/features/projects/hooks";
import { type ProjectFormCommand, ProjectFormDrawer } from "#/features/projects/ProjectFormDrawer";
import { ProjectsTable } from "#/features/projects/ProjectsTable";
import { useOnDemandTotal } from "#/hooks/useOnDemandTotal";
import { useI18n } from "#/i18n";
import { formatDateTime } from "#/lib";
import { type ClientFormCommand, ClientFormDrawer } from "./ClientFormDrawer";
import { ClientStatusChip } from "./ClientStatusChip";
import { clientQuery, useDeleteClient } from "./hooks";

const route = getRouteApi("/_app/clients/$clientId");

export function ClientDetailsPage() {
	const { t, locale } = useI18n();
	const { clientId } = route.useParams();
	const me = useMe();
	const navigate = useNavigate();
	const client = useQuery(clientQuery(clientId));
	const projects = useInfiniteQuery(projectsQuery({ clientId }, 10));
	const projectsTotal = useOnDemandTotal(projectsCountQuery({ clientId }));
	const clientDrawer = useRef<ClientFormCommand>(null);
	const projectDrawer = useRef<ProjectFormCommand>(null);
	const offerDialog = useRef<NewOfferCommand>(null);
	const [confirmDelete, setConfirmDelete] = useState(false);
	const remove = useDeleteClient(() => {
		toast.success(t("Usunięto klienta", "Client deleted"));
		void navigate({ to: "/clients" });
	});

	if (client.isPending) {
		return (
			<div className="flex flex-col gap-4">
				<Skeleton className="h-10 w-1/2 rounded-md" />
				<Skeleton className="h-48 w-full rounded-lg" />
			</div>
		);
	}
	if (client.isError)
		return (
			<ApiError
				error={client.error}
				title={t("Nie udało się wczytać klienta", "Client could not be loaded")}
			/>
		);
	const c = client.data;
	const list = projects.data?.pages.flatMap((p) => p.items) ?? [];

	return (
		<>
			<Link
				to="/clients"
				className="mb-6 inline-flex items-center gap-1.5 text-sm text-muted hover:text-foreground"
			>
				<ArrowLeft className="size-4" /> {t("Klienci", "Clients")}
			</Link>
			<PageHeader
				eyebrow={
					<span className="figures">
						{t("Klient", "Client")} #{c.id}
					</span>
				}
				title={c.name}
				meta={
					<>
						<ClientStatusChip status={c.status} />
						{c.nip ? <span className="figures text-xs text-muted">NIP {c.nip}</span> : null}
					</>
				}
				actions={
					<>
						<Button variant="secondary" onPress={() => clientDrawer.current?.edit(c)}>
							<Pencil className="size-4" /> {t("Edytuj", "Edit")}
						</Button>
						{can.deleteClients(me.role) ? (
							<Button variant="danger-soft" onPress={() => setConfirmDelete(true)}>
								<Trash2 className="size-4" /> {t("Usuń", "Delete")}
							</Button>
						) : null}
					</>
				}
			/>

			<div className="grid gap-6 lg:grid-cols-3">
				<Card className="lg:col-span-2">
					<Card.Header>
						<Card.Title className="font-display text-xl">{t("Kontakt", "Contact")}</Card.Title>
					</Card.Header>
					<Card.Content>
						<div className="grid gap-4 sm:grid-cols-3">
							<ContactTile
								icon={Mail}
								label="E-mail"
								value={c.email}
								href={c.email ? `mailto:${c.email}` : undefined}
							/>
							<ContactTile
								icon={Phone}
								label={t("Telefon", "Phone")}
								value={c.phone}
								href={c.phone ? `tel:${c.phone}` : undefined}
							/>
							<ContactTile icon={MapPin} label={t("Miasto", "City")} value={c.city} />
						</div>
						{c.note ? (
							<blockquote className="mt-6 border-l-2 border-champagne pl-4 text-sm text-foreground/80 italic">
								{c.note}
							</blockquote>
						) : null}
					</Card.Content>
				</Card>
				<Card>
					<Card.Header>
						<Card.Title className="font-display text-xl">{t("Konto", "Account")}</Card.Title>
					</Card.Header>
					<Card.Content>
						<InfoList
							items={[
								{
									label: t("Opiekun", "Owner"),
									value: (
										<span className="font-mono text-xs">
											{c.assignedUserLogin ?? t("nieprzypisany", "unassigned")}
										</span>
									),
								},
								{ label: t("Utworzono", "Created"), value: formatDateTime(c.createdAt, locale) },
								{ label: t("Zmieniono", "Updated"), value: formatDateTime(c.updatedAt, locale) },
								{
									label: t("Wersja", "Version"),
									value: <span className="figures text-xs text-muted">{c.rowVersion}</span>,
								},
							]}
						/>
					</Card.Content>
				</Card>
			</div>

			<Card className="mt-6 overflow-hidden p-0">
				<div className="flex items-center justify-between border-b border-separator px-5 py-4">
					<h2 className="font-display text-xl font-semibold">{t("Projekty", "Projects")}</h2>
					<Button
						size="sm"
						onPress={() => projectDrawer.current?.create({ id: c.id, name: c.name })}
					>
						<Plus className="size-4" /> {t("Nowy projekt", "New project")}
					</Button>
				</div>
				{projects.isPending ? (
					<TableSkeleton rows={3} />
				) : list.length === 0 ? (
					<EmptyState
						icon={BriefcaseBusiness}
						title={t("Nie ma jeszcze projektów", "No projects yet")}
						description={t(
							"Projekt realizuje zespół, a jego właścicielem jest jeden z członków zespołu.",
							"A project is delivered by a team and owned by one of its members.",
						)}
					/>
				) : (
					<>
						<ProjectsTable projects={list} hide={["client"]} />
						<LoadMore
							noun={t("projektów", "projects")}
							shown={list.length}
							hasMore={projects.hasNextPage}
							isLoading={projects.isFetchingNextPage}
							onLoadMore={() => void projects.fetchNextPage()}
							total={projectsTotal}
						/>
					</>
				)}
			</Card>

			<ClientOffers
				clientId={c.id}
				onNew={() => offerDialog.current?.open({ id: c.id, name: c.name })}
			/>

			<NewOfferDialog
				ref={offerDialog}
				onCreated={(o) => void navigate({ to: "/offers/$offerId", params: { offerId: o.id } })}
			/>
			<ClientFormDrawer
				ref={clientDrawer}
				onSaved={() => toast.success(t("Zapisano klienta", "Client saved"))}
			/>
			<ProjectFormDrawer
				ref={projectDrawer}
				onSaved={(p) => {
					toast.success(t(`Dodano projekt „${p.name}”`, `Project "${p.name}" created`));
					void navigate({ to: "/projects/$projectId", params: { projectId: p.id } });
				}}
			/>
			<ConfirmDialog
				isOpen={confirmDelete}
				title={t("Usunąć tego klienta?", "Delete this client?")}
				description={t(
					`Klient „${c.name}” zostanie usunięty. Klienta z projektami nie można usunąć - zamiast tego ustaw status „Nieaktywny”.`,
					`"${c.name}" will be removed. A client with projects cannot be deleted - set it to Inactive instead.`,
				)}
				confirmLabel={t("Usuń klienta", "Delete client")}
				isPending={remove.isPending}
				error={remove.error}
				onConfirm={() => remove.mutate({ id: c.id, rowVersion: c.rowVersion })}
				onClose={() => {
					setConfirmDelete(false);
					remove.reset();
				}}
			/>
		</>
	);
}

function ContactTile({
	icon: Icon,
	label,
	value,
	href,
}: {
	icon: typeof Mail;
	label: string;
	value?: string | null;
	href?: string;
}) {
	return (
		<div className="flex items-start gap-3 rounded-lg bg-surface-secondary p-3">
			<Icon className="mt-0.5 size-4 shrink-0 text-champagne" strokeWidth={1.75} />
			<div className="min-w-0">
				<p className="font-mono text-[10px] tracking-[0.1em] text-muted uppercase">{label}</p>
				{value ? (
					href ? (
						<a href={href} className="block truncate text-sm text-foreground hover:underline">
							{value}
						</a>
					) : (
						<p className="truncate text-sm text-foreground">{value}</p>
					)
				) : (
					<p className="text-sm text-muted">—</p>
				)}
			</div>
		</div>
	);
}
