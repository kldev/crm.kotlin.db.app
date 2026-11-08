import { Button, Card, Chip, Skeleton } from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { getRouteApi, Link } from "@tanstack/react-router";
import { AlarmClock, CalendarPlus, ListPlus, MessageSquarePlus, Pencil } from "lucide-react";
import { useRef } from "react";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError, EmptyState, InfoList, UserAvatar } from "#/components/ui";
import { DealDrawer, type DealDrawerCommand } from "#/features/pipeline/DealDrawer";
import { dealStagesQuery } from "#/features/pipeline/hooks";
import { amount, stageAccent, stageName } from "#/features/pipeline/types";
import { TaskDrawer, type TaskDrawerCommand } from "#/features/tasks/TaskDrawer";
import { useI18n } from "#/i18n";
import { type ActivityCommand, ActivityDialog } from "./ActivityDialog";
import { activityTypesQuery, dealActivitiesQuery, dealQuery } from "./hooks";
import { type NextStepCommand, NextStepDialog } from "./NextStepDialog";
import { ACTIVITY_ICONS, activityName, when } from "./types";

const route = getRouteApi("/_app/pipeline/$dealId");

/**
 * One deal (ADR-0017): its next step on top - the thing a salesperson must not miss - and what happened so far, newest
 * first. From here a contact is logged, the next step planned and a task of the deal added.
 */
export function DealPage() {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const { dealId } = route.useParams();
	const deal = useQuery(dealQuery(dealId));
	const activities = useQuery(dealActivitiesQuery(dealId));
	const types = useQuery(activityTypesQuery());
	const stages = useQuery(dealStagesQuery());
	const activityDialog = useRef<ActivityCommand>(null);
	const nextStepDialog = useRef<NextStepCommand>(null);
	const taskDrawer = useRef<TaskDrawerCommand>(null);
	const dealDrawer = useRef<DealDrawerCommand>(null);

	if (deal.isError) return <ApiError error={deal.error} />;
	if (!deal.data) return <Skeleton className="h-64 rounded-lg" />;
	const d = deal.data;
	const stage = stages.data?.find((s) => s.stage === d.stage);
	const overdue = d.nextStepAt != null && new Date(d.nextStepAt).getTime() < Date.now();
	const date = (iso: string) =>
		new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(new Date(`${iso}T00:00:00`));

	return (
		<>
			<PageHeader
				eyebrow={
					<Link to="/pipeline" className="hover:underline">
						{t("Lejek sprzedaży", "Sales pipeline")}
					</Link>
				}
				title={d.title}
				description={`${d.clientName} · ${d.ownerName}`}
				actions={
					<div className="flex flex-wrap gap-2">
						<Button onPress={() => activityDialog.current?.open(d)}>
							<MessageSquarePlus className="size-4" />
							{t("Zapisz kontakt", "Log a contact")}
						</Button>
						<Button
							variant="secondary"
							onPress={() => taskDrawer.current?.create({ deal: { id: d.id, title: d.title } })}
						>
							<ListPlus className="size-4" />
							{t("Dodaj zadanie", "Add a task")}
						</Button>
						<Button variant="ghost" onPress={() => dealDrawer.current?.edit(d)}>
							<Pencil className="size-4" />
							{t("Edytuj", "Edit")}
						</Button>
					</div>
				}
			/>
			<div className="grid gap-5 lg:grid-cols-[1fr_22rem]">
				<div className="flex flex-col gap-5">
					<Card
						className={`border-l-4 ${d.closed ? "border-l-[var(--obs-border)]" : overdue ? "border-l-[var(--obs-danger)]" : d.nextStep ? "border-l-[var(--obs-champagne)]" : "border-l-[var(--obs-warning)]"}`}
					>
						<Card.Content className="flex flex-col gap-3 sm:flex-row sm:items-center">
							<AlarmClock
								className={`size-6 shrink-0 ${overdue ? "text-[var(--obs-danger)]" : "text-[var(--obs-champagne)]"}`}
							/>
							<div className="flex min-w-0 flex-1 flex-col gap-0.5">
								<span className="font-mono text-[11px] tracking-[0.08em] text-muted uppercase">
									{t("Następny krok", "Next step")}
								</span>
								{d.closed ? (
									<span className="text-sm text-muted">
										{t(
											"Szansa zamknięta - bez kolejnych kroków.",
											"The deal is closed - no further steps.",
										)}
									</span>
								) : d.nextStep && d.nextStepAt ? (
									<>
										<span className="font-display text-xl font-semibold text-foreground">
											{d.nextStep}
										</span>
										<span
											className={`text-sm ${overdue ? "font-medium text-[var(--obs-danger)]" : "text-muted"}`}
										>
											{overdue ? `${t("Zaległe", "Overdue")} · ` : ""}
											{when(d.nextStepAt, locale, t)}
										</span>
									</>
								) : (
									<span className="text-sm text-[var(--obs-warning)]">
										{t(
											"Brak zaplanowanego kroku - zaplanuj, zanim szansa wystygnie.",
											"Nothing planned - plan it before the deal goes cold.",
										)}
									</span>
								)}
							</div>
							{d.closed ? null : (
								<div className="flex gap-2">
									{d.nextStep ? (
										<Button size="sm" onPress={() => activityDialog.current?.open(d)}>
											{t("Zrobione", "Done")}
										</Button>
									) : null}
									<Button
										size="sm"
										variant="secondary"
										onPress={() => nextStepDialog.current?.open(d)}
									>
										<CalendarPlus className="size-4" />
										{d.nextStep ? t("Przełóż", "Reschedule") : t("Zaplanuj", "Plan")}
									</Button>
								</div>
							)}
						</Card.Content>
					</Card>

					<Card className="p-0">
						<Card.Header className="border-b border-separator px-5 py-3">
							<Card.Title className="text-base">{t("Aktywność", "Activity")}</Card.Title>
						</Card.Header>
						<Card.Content className="p-0">
							{activities.isError ? (
								<div className="p-4">
									<ApiError error={activities.error} />
								</div>
							) : (activities.data ?? []).length === 0 ? (
								<EmptyState
									icon={MessageSquarePlus}
									title={t("Jeszcze bez kontaktu", "No contact yet")}
									description={t(
										"Zapisz pierwszą rozmowę, e-mail albo spotkanie.",
										"Log the first call, e-mail or meeting.",
									)}
								/>
							) : (
								<ol className="flex flex-col">
									{(activities.data ?? []).map((a) => {
										const Icon = ACTIVITY_ICONS[a.type] ?? ACTIVITY_ICONS.OTHER;
										return (
											<li
												key={a.id}
												className="flex gap-3 border-b border-separator/60 px-5 py-3 last:border-b-0"
											>
												<span className="mt-0.5 grid size-8 shrink-0 place-items-center rounded-full bg-[var(--obs-surface-subtle)] text-[var(--obs-text-secondary)]">
													<Icon className="size-4" />
												</span>
												<div className="flex min-w-0 flex-1 flex-col gap-0.5">
													<span className="flex flex-wrap items-baseline gap-x-2 text-xs text-muted">
														<span className="font-semibold text-[var(--obs-text-secondary)]">
															{activityName(a.type, types.data, i18n)}
														</span>
														<span>{when(a.occurredAt, locale, t)}</span>
														<span>· {a.createdByName}</span>
													</span>
													<p className="whitespace-pre-line text-sm text-foreground">{a.note}</p>
												</div>
											</li>
										);
									})}
								</ol>
							)}
						</Card.Content>
					</Card>
				</div>

				<Card className="self-start">
					<Card.Content>
						<InfoList
							items={[
								{
									label: t("Klient", "Client"),
									value: (
										<Link
											to="/clients/$clientId"
											params={{ clientId: d.clientId }}
											className="hover:underline"
										>
											{d.clientName}
										</Link>
									),
								},
								{
									label: t("Etap", "Stage"),
									value: (
										<span className="flex items-center gap-2">
											<span
												className="size-2.5 rounded-full"
												style={{ background: stageAccent[d.stage] }}
											/>
											{stage ? stageName(stage, i18n) : d.stage}
											<Chip size="sm" variant="soft">
												{d.probability}%
											</Chip>
										</span>
									),
								},
								{
									label: t("Wartość", "Value"),
									value: <span className="figures">{amount(d, locale)}</span>,
								},
								{ label: t("Zamknięcie", "Expected close"), value: date(d.expectedClose) },
								{
									label: t("Opiekun", "Owner"),
									value: (
										<span className="flex items-center gap-2">
											<UserAvatar name={d.ownerName} />
											{d.ownerName}
										</span>
									),
								},
								...(d.offerNumber
									? [
											{
												label: t("Oferta", "Offer"),
												value: (
													<Link
														to="/offers/$offerId"
														params={{ offerId: d.offerId ?? 0 }}
														className="font-mono text-xs hover:underline"
													>
														{d.offerNumber}
													</Link>
												),
											},
										]
									: []),
								{
									label: t("Ostatni kontakt", "Last contact"),
									value: d.lastActivityAt
										? `${activityName(d.lastActivityType ?? "", types.data, i18n)}, ${when(d.lastActivityAt, locale, t)}`
										: "—",
								},
								...(d.lostReason
									? [{ label: t("Powód przegranej", "Lost because"), value: d.lostReason }]
									: []),
							]}
						/>
					</Card.Content>
				</Card>
			</div>
			<ActivityDialog ref={activityDialog} />
			<NextStepDialog ref={nextStepDialog} />
			<TaskDrawer ref={taskDrawer} />
			<DealDrawer ref={dealDrawer} board={{ scope: "ALL" }} />
		</>
	);
}
