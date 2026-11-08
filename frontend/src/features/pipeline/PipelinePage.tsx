import {
	Button,
	SearchField,
	Skeleton,
	ToggleButton,
	ToggleButtonGroup,
	toast,
} from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { getRouteApi, useNavigate } from "@tanstack/react-router";
import { CircleDollarSign, Plus, Scale, Trophy, XCircle } from "lucide-react";
import { type DragEvent, useRef, useState } from "react";
import type { DealResponse, DealStageResponse } from "#/api/models";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError, UserAvatar } from "#/components/ui";
import { useMe } from "#/features/auth/session";
import { StatTile } from "#/features/desk/charts/ChartKit";
import { useDebouncedValue } from "#/hooks/useDebouncedValue";
import { useI18n } from "#/i18n";
import { problemText } from "#/i18n/problems";
import { DealDrawer, type DealDrawerCommand } from "./DealDrawer";
import { dealBoardQuery, dealStagesQuery, dealSummaryQuery, useMoveDeal } from "./hooks";
import { LostReasonDialog } from "./LostReasonDialog";
import { amount, countOf, type DealScope, stageAccent, stageName, summed } from "./types";

const route = getRouteApi("/_app/pipeline/");

const DRAG_TYPE = "application/x-crm-deal";

/**
 * The sales pipeline as a kanban board (ADR-0015): a column per stage, a card per deal, dragged to the next stage.
 * Closed deals stay on the board for 30 days. The column heads and the tiles sum the value and the forecast
 * weighted by the stage's probability.
 */
export function PipelinePage() {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const me = useMe();
	const search = route.useSearch();
	const navigate = route.useNavigate();
	const drawer = useRef<DealDrawerCommand>(null);
	const goTo = useNavigate();
	// A salesperson starts with their own deals; managers see the whole team.
	const scope: DealScope = search.scope ?? (me.role === "SALES" ? "MINE" : "ALL");
	const [text, setText] = useState(search.q ?? "");
	const q = useDebouncedValue(text.trim(), 300);
	if ((search.q ?? "") !== q)
		void navigate({ search: (s) => ({ ...s, q: q || undefined }), replace: true });

	const board = { scope, search: search.q };
	const stages = useQuery(dealStagesQuery());
	const query = useQuery(dealBoardQuery(board));
	const deals = query.data ?? [];
	const [dragging, setDragging] = useState<number | null>(null);
	const [over, setOver] = useState<string | null>(null);
	const [losing, setLosing] = useState<DealResponse | null>(null);
	const move = useMoveDeal(board);

	// The tiles and the column heads count every matching deal (app.deal_board_summary), the columns show the first cards.
	const summary = useQuery(dealSummaryQuery(board)).data ?? [];
	const closedStages = new Set((stages.data ?? []).filter((s) => s.closed).map((s) => s.stage));
	const open = summary.filter((r) => !closedStages.has(r.stage));
	const won = summary.filter((r) => r.stage === "WON");
	const lost = summary.filter((r) => r.stage === "LOST");
	const wonCount = countOf(won);
	const lostCount = countOf(lost);
	const winRate = wonCount + lostCount === 0 ? null : wonCount / (wonCount + lostCount);

	const drop = (stage: DealStageResponse, event: DragEvent) => {
		event.preventDefault();
		setOver(null);
		const id = Number(event.dataTransfer.getData(DRAG_TYPE));
		const deal = deals.find((d) => d.id === id);
		if (!deal || deal.stage === stage.stage) return;
		if (stage.stage === "LOST") {
			setLosing(deal);
			return;
		}
		move.mutate(
			{ id: deal.id, stage: stage.stage, rowVersion: deal.rowVersion },
			{
				onSuccess: () =>
					toast.success(t(`${deal.title} → ${stage.namePl}`, `${deal.title} → ${stage.nameEn}`)),
				onError: (e) => toast.danger(problemText(e, i18n)),
			},
		);
	};

	return (
		<>
			<PageHeader
				eyebrow="CRM"
				title={t("Lejek sprzedaży", "Sales pipeline")}
				description={t(
					"Szanse sprzedaży od pierwszego kontaktu do wygranej. Przeciągnij kartę do kolejnego etapu.",
					"Deals from the first contact to the win. Drag a card to the next stage.",
				)}
				actions={
					<Button onPress={() => drawer.current?.create()}>
						<Plus className="size-4" />
						{t("Nowa szansa", "New deal")}
					</Button>
				}
			/>
			<div className="mb-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
				<StatTile
					icon={CircleDollarSign}
					label={t("W lejku", "In the pipeline")}
					value={summed(open, locale)}
					note={t(`${countOf(open)} otwartych szans`, `${countOf(open)} open deals`)}
				/>
				<StatTile
					icon={Scale}
					label={t("Prognoza ważona", "Weighted forecast")}
					value={summed(open, locale, true)}
					note={t("wartość × prawdopodobieństwo etapu", "value × the stage's probability")}
				/>
				<StatTile
					icon={Trophy}
					label={t("Wygrane (30 dni)", "Won (30 days)")}
					value={summed(won, locale)}
					note={t(`${wonCount} szans`, `${wonCount} deals`)}
				/>
				<StatTile
					icon={XCircle}
					tone={winRate != null && winRate < 0.5 ? "warning" : undefined}
					label={t("Skuteczność (30 dni)", "Win rate (30 days)")}
					value={winRate == null ? "—" : `${Math.round(winRate * 100)}%`}
					note={t(
						`${wonCount} wygr. · ${lostCount} przegr.`,
						`${wonCount} won · ${lostCount} lost`,
					)}
				/>
			</div>
			<div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center">
				<ToggleButtonGroup
					aria-label={t("Czyje szanse", "Whose deals")}
					selectionMode="single"
					disallowEmptySelection
					size="sm"
					selectedKeys={new Set([scope])}
					onSelectionChange={(keys) => {
						const next = [...keys][0] as DealScope;
						void navigate({ search: (s) => ({ ...s, scope: next }), replace: true });
					}}
				>
					<ToggleButton id="MINE">{t("Moje", "Mine")}</ToggleButton>
					<ToggleButton id="ALL">
						{me.role === "SALES" ? t("Moich klientów", "My clients'") : t("Wszystkie", "All")}
					</ToggleButton>
				</ToggleButtonGroup>
				<SearchField
					aria-label={t("Szukaj szans", "Search deals")}
					className="w-full sm:max-w-xs"
					value={text}
					onChange={setText}
				>
					<SearchField.Group>
						<SearchField.SearchIcon />
						<SearchField.Input
							placeholder={t("Nazwa szansy albo klienta…", "Deal or client name…")}
						/>
						<SearchField.ClearButton />
					</SearchField.Group>
				</SearchField>
			</div>
			{query.isError ? (
				<ApiError error={query.error} />
			) : query.isPending || !stages.data ? (
				<div className="grid grid-cols-6 gap-3">
					{Array.from({ length: 6 }, (_, i) => (
						<Skeleton key={`s${i}`} className="h-96 rounded-lg" />
					))}
				</div>
			) : (
				<div className="overflow-x-auto pb-2">
					<div
						className="grid gap-3"
						style={{ gridTemplateColumns: `repeat(${stages.data.length}, minmax(250px, 1fr))` }}
					>
						{stages.data.map((stage) => {
							const cards = deals.filter((d) => d.stage === stage.stage);
							const rows = summary.filter((r) => r.stage === stage.stage);
							const total = Math.max(countOf(rows), cards.length);
							const isOver = over === stage.stage && dragging != null;
							return (
								<section
									key={stage.stage}
									aria-label={stageName(stage, i18n)}
									onDragOver={(e) => {
										if (!e.dataTransfer.types.includes(DRAG_TYPE)) return;
										e.preventDefault();
										e.dataTransfer.dropEffect = "move";
										setOver(stage.stage);
									}}
									onDragLeave={(e) => {
										if (!e.currentTarget.contains(e.relatedTarget as Node)) setOver(null);
									}}
									onDrop={(e) => drop(stage, e)}
									className={`flex min-h-[28rem] flex-col rounded-lg border bg-[var(--obs-surface-subtle)] transition-colors ${isOver ? "border-[var(--obs-champagne)] bg-[var(--obs-champagne-soft)]" : "border-separator"}`}
								>
									<header
										className="border-b border-separator px-3 pt-3 pb-2.5"
										style={{ boxShadow: `inset 0 3px 0 ${stageAccent[stage.stage]}` }}
									>
										<div className="flex items-center justify-between gap-2">
											<h2 className="text-sm font-semibold text-foreground">
												{stageName(stage, i18n)}
											</h2>
											<span className="rounded-full bg-[var(--obs-surface)] px-2 py-0.5 text-[11px] tabular-nums text-muted">
												{total}
											</span>
										</div>
										<p className="mt-1 text-xs tabular-nums text-[var(--obs-text-secondary)]">
											{summed(rows, locale)}
										</p>
										<p className="text-[11px] text-muted">
											{stage.closed
												? t("ostatnie 30 dni", "last 30 days")
												: t(
														`${stage.probability}% · prognoza ${summed(rows, locale, true)}`,
														`${stage.probability}% · forecast ${summed(rows, locale, true)}`,
													)}
										</p>
									</header>
									<div className="flex flex-1 flex-col gap-2 p-2">
										{cards.map((deal) => (
											<DealCard
												key={deal.id}
												deal={deal}
												showOwner={scope === "ALL" && me.role !== "SALES"}
												isDragging={dragging === deal.id}
												onOpen={() =>
													void goTo({ to: "/pipeline/$dealId", params: { dealId: deal.id } })
												}
												onDragStart={(e) => {
													e.dataTransfer.setData(DRAG_TYPE, String(deal.id));
													e.dataTransfer.effectAllowed = "move";
													setDragging(deal.id);
												}}
												onDragEnd={() => {
													setDragging(null);
													setOver(null);
												}}
											/>
										))}
										{total > cards.length ? (
											<p className="py-1 text-center text-[11px] text-muted">
												{t(
													`Pokazano ${cards.length} z ${total} - zawęź wyszukiwaniem`,
													`Showing ${cards.length} of ${total} - narrow it with the search`,
												)}
											</p>
										) : null}
										{!stage.closed ? (
											<button
												type="button"
												onClick={() => drawer.current?.create(stage.stage)}
												className="mt-auto flex items-center justify-center gap-1 rounded-md border border-dashed border-separator py-2 text-xs text-muted transition-colors hover:border-[var(--obs-border-strong)] hover:text-foreground"
											>
												<Plus className="size-3.5" />
												{t("Dodaj", "Add")}
											</button>
										) : null}
									</div>
								</section>
							);
						})}
					</div>
				</div>
			)}
			<DealDrawer ref={drawer} board={board} />
			<LostReasonDialog deal={losing} board={board} onClose={() => setLosing(null)} />
		</>
	);
}

function DealCard({
	deal,
	showOwner,
	isDragging,
	onOpen,
	onDragStart,
	onDragEnd,
}: {
	deal: DealResponse;
	showOwner: boolean;
	isDragging: boolean;
	onOpen: () => void;
	onDragStart: (e: DragEvent) => void;
	onDragEnd: () => void;
}) {
	const { t, locale } = useI18n();
	const today = new Date().toISOString().slice(0, 10);
	const late = !deal.closed && deal.expectedClose < today;
	const date = new Intl.DateTimeFormat(locale, { day: "numeric", month: "short" }).format(
		new Date(`${deal.expectedClose}T00:00:00`),
	);
	const days = Math.max(
		0,
		Math.floor((Date.now() - new Date(deal.stageChangedAt).getTime()) / 86_400_000),
	);
	return (
		<button
			type="button"
			draggable
			onDragStart={onDragStart}
			onDragEnd={onDragEnd}
			onClick={onOpen}
			className={`group flex cursor-grab flex-col gap-1.5 rounded-md border border-separator bg-[var(--obs-surface)] p-3 text-left shadow-[0_1px_2px_rgb(23_26_33/0.06)] transition-[box-shadow,opacity] hover:shadow-[0_3px_10px_rgb(23_26_33/0.10)] active:cursor-grabbing ${isDragging ? "opacity-40" : ""} ${deal.stage === "LOST" ? "opacity-75" : ""}`}
		>
			<span className="line-clamp-2 text-sm font-medium leading-snug text-foreground">
				{deal.title}
			</span>
			<span className="truncate text-xs text-muted">{deal.clientName}</span>
			<span className="font-display text-lg font-semibold tabular-nums text-[var(--obs-ink)]">
				{amount(deal, locale)}
			</span>
			<span className="flex items-center justify-between gap-2 text-[11px]">
				<span className={late ? "font-medium text-[var(--obs-danger)]" : "text-muted"}>
					{deal.closed ? t("zamknięta ", "closed ") : late ? t("termin minął ", "overdue ") : ""}
					{date}
				</span>
				<span className="text-muted" title={t("Dni w tym etapie", "Days in this stage")}>
					{t(`${days} d.`, `${days} d`)}
				</span>
			</span>
			{deal.lostReason ? (
				<span className="line-clamp-2 text-[11px] text-[var(--obs-danger)]">{deal.lostReason}</span>
			) : null}
			{showOwner || deal.offerNumber ? (
				<span className="flex items-center justify-between gap-2 border-t border-[var(--obs-border-subtle)] pt-1.5">
					{showOwner ? (
						<span className="flex min-w-0 items-center gap-1.5 text-[11px] text-muted">
							<UserAvatar name={deal.ownerName} />
							<span className="truncate">{deal.ownerName}</span>
						</span>
					) : (
						<span />
					)}
					{deal.offerNumber ? (
						<span className="font-mono text-[10px] text-muted">{deal.offerNumber}</span>
					) : null}
				</span>
			) : null}
		</button>
	);
}
