import {
	Button,
	Card,
	Chip,
	Label,
	Skeleton,
	Tabs,
	TextArea,
	TextField,
	toast,
} from "@heroui/react";
import { useInfiniteQuery, useQuery } from "@tanstack/react-query";
import { getRouteApi, Link } from "@tanstack/react-router";
import { ArrowLeft, CalendarClock, History, MessageSquare, Pencil, Send } from "lucide-react";
import { useRef, useState } from "react";
import type { ProjectResponse } from "#/api/models";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError, EmptyState, InfoList, UserAvatar } from "#/components/ui";
import { NEXT_STAGES, type Stage, stageAction, stageLabel } from "#/features/types";
import { useI18n } from "#/i18n";
import { daysUntil, formatDate, formatDateTime, formatMoney, formatRelative } from "#/lib";
import { projectCommentsQuery, projectQuery, projectStagesQuery, useAddComment } from "./hooks";
import { type ProjectFormCommand, ProjectFormDrawer } from "./ProjectFormDrawer";
import { StageChip } from "./StageChip";
import { StageDialog } from "./StageDialog";
import { StagePath } from "./StagePath";

const route = getRouteApi("/_app/projects/$projectId");

export function ProjectDetailsPage() {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const { projectId } = route.useParams();
	const search = route.useSearch();
	const navigate = route.useNavigate();
	const project = useQuery(projectQuery(projectId));
	const drawer = useRef<ProjectFormCommand>(null);
	const [stageTarget, setStageTarget] = useState<Stage | null>(null);

	if (project.isPending) {
		return (
			<div className="flex flex-col gap-4">
				<Skeleton className="h-10 w-1/2 rounded-md" />
				<Skeleton className="h-12 w-2/3 rounded-full" />
				<Skeleton className="h-56 w-full rounded-lg" />
			</div>
		);
	}
	if (project.isError)
		return (
			<ApiError
				error={project.error}
				title={t("Nie udało się wczytać projektu", "Project could not be loaded")}
			/>
		);
	const p = project.data;
	const stage = p.stage as Stage;
	const next = NEXT_STAGES[stage];
	const isFinal = next.length === 0;

	return (
		<>
			<Link
				to="/projects"
				className="mb-6 inline-flex items-center gap-1.5 text-sm text-muted hover:text-foreground"
			>
				<ArrowLeft className="size-4" /> {t("Projekty", "Projects")}
			</Link>
			<PageHeader
				eyebrow={
					<span className="figures">
						{t("Projekt", "Project")} #{p.id}
					</span>
				}
				title={p.name}
				meta={
					<>
						<StageChip stage={p.stage} size="md" />
						{p.overdue ? (
							<Chip size="md" variant="soft" color="danger">
								{t("Po terminie", "Overdue")}
							</Chip>
						) : null}
						<span className="text-xs text-muted">
							{t("na tym etapie od", "in stage since")} {formatRelative(p.stageChangedAt, locale)}
						</span>
					</>
				}
				actions={
					<>
						{next.map((target) => (
							<Button
								key={target}
								variant={
									target === "DECLINED"
										? "danger-soft"
										: target === "ON_HOLD"
											? "secondary"
											: undefined
								}
								onPress={() => setStageTarget(target)}
							>
								{stageAction(target, i18n)}
							</Button>
						))}
						{isFinal ? null : (
							<Button variant="secondary" onPress={() => drawer.current?.edit(p)}>
								<Pencil className="size-4" /> {t("Edytuj", "Edit")}
							</Button>
						)}
					</>
				}
			/>

			<div className="mb-6">
				<StagePath stage={stage} />
			</div>

			<div className="grid gap-6 lg:grid-cols-3">
				<Card className="lg:col-span-1">
					<Card.Header>
						<Card.Title className="font-display text-xl">{t("Szczegóły", "Details")}</Card.Title>
					</Card.Header>
					<Card.Content>
						<InfoList
							items={[
								{
									label: t("Klient", "Client"),
									value: (
										<Link
											to="/clients/$clientId"
											params={{ clientId: p.clientId }}
											className="font-medium hover:underline"
										>
											{p.clientName}
										</Link>
									),
								},
								{
									label: t("Zespół", "Team"),
									value: (
										<Link
											to="/teams/$teamId"
											params={{ teamId: p.teamId }}
											className="hover:underline"
										>
											{p.teamName}
										</Link>
									),
								},
								{
									label: t("Właściciel", "Owner"),
									value: (
										<span className="flex items-center gap-2">
											<UserAvatar name={p.ownerDisplayName} />
											<span className="flex flex-col leading-tight">
												<span>{p.ownerDisplayName}</span>
												<span className="font-mono text-[11px] text-muted">{p.ownerLogin}</span>
											</span>
										</span>
									),
								},
								{ label: t("Rozpoczęcie", "Start"), value: formatDate(p.startDate, locale) },
								{ label: t("Termin", "Due"), value: <DueLine project={p} /> },
								{
									label: t("Budżet", "Budget"),
									value: <span className="figures">{formatMoney(p.budget)}</span>,
								},
								{ label: t("Zmieniono", "Updated"), value: formatDateTime(p.updatedAt, locale) },
							]}
						/>
					</Card.Content>
				</Card>

				<Card className="p-0 lg:col-span-2">
					<Tabs
						className="w-full"
						selectedKey={search.tab ?? "comments"}
						onSelectionChange={(key) =>
							void navigate({
								search: { tab: key === "history" ? "history" : undefined },
								replace: true,
							})
						}
					>
						<Tabs.ListContainer className="border-b border-separator px-4 pt-3">
							<Tabs.List aria-label={t("Aktywność projektu", "Project activity")}>
								<Tabs.Tab id="comments">
									<MessageSquare className="size-4" /> {t("Komentarze", "Comments")}
									<Tabs.Indicator />
								</Tabs.Tab>
								<Tabs.Tab id="history">
									<History className="size-4" /> {t("Historia etapów", "Stage history")}
									<Tabs.Indicator />
								</Tabs.Tab>
							</Tabs.List>
						</Tabs.ListContainer>
						<Tabs.Panel id="comments" className="p-5">
							<Comments projectId={p.id} />
						</Tabs.Panel>
						<Tabs.Panel id="history" className="p-5">
							<StageHistory projectId={p.id} />
						</Tabs.Panel>
					</Tabs>
				</Card>
			</div>

			<ProjectFormDrawer
				ref={drawer}
				onSaved={() => toast.success(t("Zapisano projekt", "Project saved"))}
			/>
			<StageDialog
				project={p}
				target={stageTarget}
				onClose={() => setStageTarget(null)}
				onChanged={(updated) => {
					setStageTarget(null);
					const label = stageLabel(updated.stage, i18n).toLowerCase();
					toast.success(t(`Etap projektu: ${label}`, `Project is now ${label}`));
				}}
			/>
		</>
	);
}

function DueLine({ project }: { project: ProjectResponse }) {
	const { t, locale } = useI18n();
	const days = daysUntil(project.dueDate);
	const open = NEXT_STAGES[project.stage as Stage].length > 0;
	return (
		<span className="flex items-center gap-2">
			<CalendarClock className={`size-4 ${project.overdue ? "text-danger" : "text-muted"}`} />
			<span className={project.overdue ? "font-semibold text-danger" : ""}>
				{formatDate(project.dueDate, locale)}
			</span>
			{open ? (
				<span className="text-xs text-muted">
					{days < 0
						? t(`${-days} ${days === -1 ? "dzień" : "dni"} po terminie`, `${-days} days late`)
						: days === 0
							? t("dziś", "today")
							: t(`za ${days} ${days === 1 ? "dzień" : "dni"}`, `in ${days} days`)}
				</span>
			) : null}
		</span>
	);
}

function Comments({ projectId }: { projectId: number }) {
	const { t, locale } = useI18n();
	const comments = useInfiniteQuery(projectCommentsQuery(projectId));
	const [text, setText] = useState("");
	const add = useAddComment(projectId, () => setText(""));
	const items = comments.data?.pages.flatMap((p) => p.items) ?? [];

	return (
		<div className="flex flex-col gap-5">
			<form
				className="flex flex-col gap-2"
				onSubmit={(event) => {
					event.preventDefault();
					if (text.trim()) add.mutate(text.trim());
				}}
			>
				<TextField
					value={text}
					onChange={setText}
					fullWidth
					aria-label={t("Nowy komentarz", "New comment")}
				>
					<Label className="sr-only">{t("Nowy komentarz", "New comment")}</Label>
					<TextArea
						rows={2}
						placeholder={t("Napisz notatkę dla zespołu…", "Write a note for the team…")}
					/>
				</TextField>
				<ApiError error={add.error} />
				<div className="flex justify-end">
					<Button type="submit" size="sm" isDisabled={!text.trim()} isPending={add.isPending}>
						<Send className="size-4" /> {t("Skomentuj", "Comment")}
					</Button>
				</div>
			</form>

			{comments.isPending ? (
				<Skeleton className="h-24 w-full rounded-lg" />
			) : comments.isError ? (
				<ApiError error={comments.error} />
			) : items.length === 0 ? (
				<EmptyState
					icon={MessageSquare}
					title={t("Nie ma jeszcze komentarzy", "No comments yet")}
					description={t(
						"Tu pojawiają się notatki i zmiany etapu z komentarzem.",
						"Notes and stage changes with a comment appear here.",
					)}
				/>
			) : (
				<ul className="flex flex-col gap-4">
					{items.map((c) => (
						<li key={c.id} className="flex gap-3">
							<UserAvatar name={c.authorDisplayName} />
							<div className="min-w-0 flex-1 rounded-lg bg-surface-secondary px-4 py-3">
								<div className="mb-1 flex flex-wrap items-baseline gap-x-2">
									<span className="text-sm font-medium">{c.authorDisplayName}</span>
									<span className="font-mono text-[11px] text-muted">{c.authorLogin}</span>
									<span
										className="ml-auto text-[11px] text-muted"
										title={formatDateTime(c.createdAt, locale)}
									>
										{formatRelative(c.createdAt, locale)}
									</span>
								</div>
								<p className="text-sm whitespace-pre-wrap text-foreground">{c.body}</p>
							</div>
						</li>
					))}
				</ul>
			)}
			{comments.hasNextPage ? (
				<Button
					variant="ghost"
					size="sm"
					className="self-center"
					isPending={comments.isFetchingNextPage}
					onPress={() => void comments.fetchNextPage()}
				>
					{t("Starsze komentarze", "Older comments")}
				</Button>
			) : null}
		</div>
	);
}

function StageHistory({ projectId }: { projectId: number }) {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const history = useQuery(projectStagesQuery(projectId));
	if (history.isPending) return <Skeleton className="h-24 w-full rounded-lg" />;
	if (history.isError) return <ApiError error={history.error} />;
	return (
		<ol className="relative ml-2 border-l border-border">
			{history.data.map((h) => (
				<li key={h.id} className="mb-6 ml-6 last:mb-0">
					<span className="absolute -left-[5px] mt-1.5 size-2.5 rounded-full border-2 border-background bg-champagne" />
					<p className="text-sm">
						{h.fromStage ? (
							<>
								<span className="text-muted">{stageLabel(h.fromStage, i18n)}</span>
								{" → "}
							</>
						) : (
							<span className="text-muted">{t("Utworzony jako", "Created as")} </span>
						)}
						<strong>{stageLabel(h.toStage, i18n)}</strong>
					</p>
					<p className="mt-0.5 text-xs text-muted">
						{formatDateTime(h.changedAt, locale)}
						{h.changedByLogin ? ` · ${h.changedByLogin}` : " · seed"}
					</p>
				</li>
			))}
		</ol>
	);
}
