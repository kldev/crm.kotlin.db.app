import { Button, Card, Skeleton, toast } from "@heroui/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Play } from "lucide-react";
import { getQueues, runJob } from "#/api/endpoints/system/system";
import { systemKeys } from "#/api/query-keys";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError } from "#/components/ui";
import { DataTable } from "#/features/desk/charts/ChartKit";
import { useI18n } from "#/i18n";
import { problemText } from "#/i18n/problems";
import { dateTime } from "./format";

/** The in-memory queues of the monitoring and its background jobs, with "run now" (ADR-0012). */
export function QueuesPage() {
	const i18n = useI18n();
	const { t } = i18n;
	const queryClient = useQueryClient();
	const state = useQuery({
		queryKey: systemKeys.queues(),
		queryFn: () => getQueues(),
		refetchInterval: 5_000,
	});
	const run = useMutation({
		mutationFn: (name: string) => runJob(name),
		onSuccess: async (job) => {
			await queryClient.invalidateQueries({ queryKey: systemKeys.all });
			toast.success(`${job.name}: ${job.lastError ?? job.lastResult ?? ""}`);
		},
		onError: (error) => toast.danger(problemText(error, i18n)),
	});
	const jobName = (n: string) =>
		n === "writer"
			? t("Zapis kolejek do bazy", "Writing the queues")
			: t("Retencja (14 dni)", "Retention (14 days)");
	return (
		<>
			<PageHeader
				eyebrow={t("System", "System")}
				title={t("Kolejki", "Queues")}
				description={t(
					"Odpowiedzi i logi czekają w pamięci; pełna kolejka odrzuca i liczy, żeby wolna baza nie spowalniała stron.",
					"Answers and log entries wait in memory; a full queue drops and counts, so a slow database never slows a page.",
				)}
			/>
			{state.isPending ? (
				<Skeleton className="h-60 w-full rounded-xl" />
			) : state.isError ? (
				<ApiError error={state.error} />
			) : (
				<div className="flex flex-col gap-6">
					<Card>
						<Card.Header>
							<Card.Title>{t("Kolejki", "Queues")}</Card.Title>
							<Card.Description>
								{t(
									`zapisane: ${state.data.written}, odrzucone przez bazę: ${state.data.failed}`,
									`written: ${state.data.written}, refused by the database: ${state.data.failed}`,
								)}
							</Card.Description>
						</Card.Header>
						<Card.Content>
							<DataTable
								head={[
									t("Kolejka", "Queue"),
									t("Czeka", "Waiting"),
									t("Pojemność", "Capacity"),
									t("Odrzucone", "Dropped"),
								]}
								rows={state.data.queues.map((q) => [
									q.name === "requests" ? t("Odpowiedzi HTTP", "HTTP answers") : t("Log", "Log"),
									q.waiting,
									q.capacity,
									q.dropped,
								])}
							/>
						</Card.Content>
					</Card>
					<Card>
						<Card.Header>
							<Card.Title>{t("Zadania w tle", "Background jobs")}</Card.Title>
						</Card.Header>
						<Card.Content>
							<ul className="divide-y divide-separator">
								{state.data.jobs.map((j) => (
									<li
										key={j.name}
										className="flex flex-wrap items-center justify-between gap-3 py-3 text-sm"
									>
										<div className="flex flex-col">
											<span className="font-medium">{jobName(j.name)}</span>
											<span className="text-xs text-muted">
												{t(
													`ostatnio: ${dateTime(j.lastRunAt, i18n, true)}`,
													`last run: ${dateTime(j.lastRunAt, i18n, true)}`,
												)}{" "}
												· {t(`uruchomień: ${j.runs}`, `runs: ${j.runs}`)}
												{j.lastResult ? ` · ${j.lastResult}` : ""}
											</span>
											{j.lastError ? (
												<span className="text-xs text-danger">{j.lastError}</span>
											) : null}
										</div>
										<Button
											size="sm"
											variant="secondary"
											isPending={run.isPending && run.variables === j.name}
											onPress={() => run.mutate(j.name)}
										>
											<Play className="size-3.5" />
											{t("Uruchom teraz", "Run now")}
										</Button>
									</li>
								))}
							</ul>
						</Card.Content>
					</Card>
				</div>
			)}
		</>
	);
}
