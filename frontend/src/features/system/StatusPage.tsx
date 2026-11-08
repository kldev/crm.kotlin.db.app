import { Card, Chip, SearchField, Skeleton, ToggleButton, ToggleButtonGroup } from "@heroui/react";
import { keepPreviousData, useInfiniteQuery, useQuery } from "@tanstack/react-query";
import { AlarmClock, CheckCircle2, Clock } from "lucide-react";
import { useState } from "react";
import { getSystemStatus, listRecordedRequests } from "#/api/endpoints/system/system";
import type { GetSystemStatusRange, PageResponseRequestEntry } from "#/api/models";
import { systemKeys } from "#/api/query-keys";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError, LoadMore, SelectFilter } from "#/components/ui";
import {
	ChartCard,
	DataTable,
	Legend,
	type Segment,
	StackedColumns,
	StatTile,
} from "#/features/desk/charts/ChartKit";
import { useDebouncedValue } from "#/hooks/useDebouncedValue";
import { useI18n } from "#/i18n";
import { dateTime, ms, statusTone } from "./format";

const OUTCOMES = ["OK", "REDIRECT", "FORBIDDEN", "NOT_FOUND", "CLIENT", "SERVER"] as const;

/**
 * System status (ADR-0012): health, HTTP answers by outcome over the range, codes, the most frequent failures, the
 * recorded answers and the effective settings with their environment variables.
 */
export function StatusPage() {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const [range, setRange] = useState<GetSystemStatusRange>("H24");
	const status = useQuery({
		queryKey: systemKeys.status(range),
		queryFn: () => getSystemStatus({ range }),
		placeholderData: keepPreviousData,
		refetchInterval: 30_000,
	});
	const segments: Segment[] = [
		{ key: "ok", label: t("2xx / 3xx", "2xx / 3xx"), color: "var(--viz-good)", icon: CheckCircle2 },
		{ key: "client", label: "4xx", color: "var(--viz-warning)", icon: Clock },
		{ key: "server", label: "5xx", color: "var(--viz-critical)", icon: AlarmClock },
	];

	return (
		<>
			<PageHeader
				eyebrow={t("System", "System")}
				title={t("Status systemu", "System status")}
				description={t(
					"Każda odpowiedź HTTP i log aplikacji, zapisywane w tle; przechowywane 14 dni.",
					"Every HTTP answer and the application log, written in the background; kept 14 days.",
				)}
				actions={
					<ToggleButtonGroup
						aria-label={t("Zakres", "Range")}
						selectionMode="single"
						disallowEmptySelection
						size="sm"
						selectedKeys={new Set([range])}
						onSelectionChange={(keys) => setRange([...keys][0] as GetSystemStatusRange)}
					>
						<ToggleButton id="H24">24 h</ToggleButton>
						<ToggleButton id="D7">{t("7 dni", "7 days")}</ToggleButton>
						<ToggleButton id="D14">{t("14 dni", "14 days")}</ToggleButton>
					</ToggleButtonGroup>
				}
			/>
			{status.isPending ? (
				<Skeleton className="h-96 w-full rounded-xl" />
			) : status.isError ? (
				<ApiError error={status.error} />
			) : (
				(() => {
					const s = status.data;
					const sum = s.summary;
					const labels = s.series.map((b) =>
						new Intl.DateTimeFormat(
							locale,
							range === "H24"
								? { hour: "2-digit", minute: "2-digit" }
								: { day: "numeric", month: "short" },
						).format(new Date(b.bucket)),
					);
					return (
						<div className={`flex flex-col gap-6 ${status.isPlaceholderData ? "opacity-60" : ""}`}>
							<div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-6">
								<StatTile
									label={t("Baza danych", "Database")}
									value={s.database}
									icon={s.database === "UP" ? CheckCircle2 : AlarmClock}
									tone={s.database === "UP" ? undefined : "danger"}
								/>
								<StatTile
									label={t("Pliki (S3)", "Files (S3)")}
									value={s.storage}
									icon={s.storage === "UP" ? CheckCircle2 : AlarmClock}
									tone={s.storage === "UP" ? undefined : "danger"}
								/>
								<StatTile
									label={t("Działa od", "Up since")}
									value={dateTime(s.startedAt, i18n)}
									note={`Java ${s.javaVersion}`}
								/>
								<StatTile
									label={t("Odpowiedzi", "Answers")}
									value={sum.total.toLocaleString(locale)}
									note={`403: ${sum.forbidden} · 404: ${sum.notFound}`}
								/>
								<StatTile
									label={t("Błędy serwera (5xx)", "Server errors (5xx)")}
									value={sum.serverError.toLocaleString(locale)}
									icon={AlarmClock}
									tone={sum.serverError > 0 ? "danger" : undefined}
									note={t(`inne 4xx: ${sum.clientError}`, `other 4xx: ${sum.clientError}`)}
								/>
								<StatTile
									label={t("Czas odpowiedzi", "Response time")}
									value={ms(sum.avgMs)}
									note={`p95: ${ms(sum.p95Ms)}`}
								/>
							</div>

							<ChartCard
								title={t("Odpowiedzi w czasie", "Answers over time")}
								description={
									range === "H24"
										? t("Na godzinę (czas warszawski).", "Per hour (Warsaw time).")
										: t("Na dzień.", "Per day.")
								}
								legend={<Legend items={segments} />}
								table={
									<DataTable
										head={[t("Okres", "Period"), ...segments.map((x) => x.label)]}
										rows={s.series.map((b, i) => [labels[i], b.ok, b.clientError, b.serverError])}
									/>
								}
							>
								<StackedColumns
									labels={labels}
									segments={segments}
									values={s.series.map((b) => [b.ok, b.clientError, b.serverError])}
								/>
							</ChartCard>

							<div className="grid gap-6 2xl:grid-cols-2">
								<Card>
									<Card.Header>
										<Card.Title>{t("Kody odpowiedzi", "Status codes")}</Card.Title>
									</Card.Header>
									<Card.Content>
										<DataTable
											head={[
												t("Kod", "Code"),
												t("Odpowiedzi", "Answers"),
												t("Średni czas", "Average time"),
											]}
											rows={s.codes.map((c) => [String(c.status), c.answers, ms(c.avgMs)])}
										/>
									</Card.Content>
								</Card>
								<Card>
									<Card.Header>
										<Card.Title>{t("Najczęstsze błędy", "Most frequent failures")}</Card.Title>
									</Card.Header>
									<Card.Content>
										{s.failing.length === 0 ? (
											<p className="text-sm text-muted">
												{t("Brak błędów w tym zakresie.", "No failures in this range.")}
											</p>
										) : (
											<DataTable
												head={[
													t("Żądanie", "Request"),
													t("Kod", "Code"),
													t("Ile", "Count"),
													t("Ostatnio", "Last"),
												]}
												rows={s.failing.map((f) => [
													`${f.method} ${f.path}`,
													String(f.status),
													f.answers,
													dateTime(f.lastAt, i18n),
												])}
											/>
										)}
									</Card.Content>
								</Card>
							</div>

							<RequestList />

							<Card>
								<Card.Header>
									<Card.Title>{t("Ustawienia", "Settings")}</Card.Title>
									<Card.Description>
										{t(
											"Techniczne, więc tylko ze zmiennych środowiskowych; tu do odczytu. Bez sekretów.",
											"Technical, so environment only; read-only here. No secrets.",
										)}
									</Card.Description>
								</Card.Header>
								<Card.Content>
									<DataTable
										head={[
											t("Zmienna", "Variable"),
											t("Wartość", "Value"),
											t("Znaczenie", "Meaning"),
										]}
										rows={s.settings.map((x) => [x.variable, x.value ?? "—", x.description])}
									/>
								</Card.Content>
							</Card>
						</div>
					);
				})()
			)}
		</>
	);
}

function RequestList() {
	const i18n = useI18n();
	const { t } = i18n;
	const [outcome, setOutcome] = useState<string | undefined>();
	const [text, setText] = useState("");
	const path = useDebouncedValue(text.trim(), 300) || undefined;
	const filters = { outcome, path };
	const list = useInfiniteQuery({
		queryKey: systemKeys.requests(filters),
		queryFn: ({ pageParam }) => listRecordedRequests({ ...filters, cursor: pageParam, size: 50 }),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (page: PageResponseRequestEntry) => page.nextCursor ?? undefined,
	});
	const items = list.data?.pages.flatMap((p) => p.items) ?? [];
	const outcomeLabel: Record<(typeof OUTCOMES)[number], string> = {
		OK: "2xx",
		REDIRECT: "3xx",
		FORBIDDEN: "403",
		NOT_FOUND: "404",
		CLIENT: t("inne 4xx", "other 4xx"),
		SERVER: "5xx",
	};
	return (
		<Card className="overflow-hidden p-0">
			<div className="flex flex-col gap-3 border-b border-separator p-4 sm:flex-row sm:items-center">
				<span className="font-medium">{t("Odpowiedzi", "Answers")}</span>
				<SelectFilter
					label={t("Wynik", "Outcome")}
					value={outcome}
					options={OUTCOMES.map((o) => ({ id: o, label: outcomeLabel[o] }))}
					onChange={setOutcome}
				/>
				<SearchField
					aria-label={t("Ścieżka", "Path")}
					className="w-full sm:max-w-xs"
					value={text}
					onChange={setText}
				>
					<SearchField.Group>
						<SearchField.SearchIcon />
						<SearchField.Input placeholder={t("Fragment ścieżki…", "Part of the path…")} />
						<SearchField.ClearButton />
					</SearchField.Group>
				</SearchField>
			</div>
			{list.isError ? (
				<div className="p-4">
					<ApiError error={list.error} />
				</div>
			) : (
				<>
					<div className="overflow-x-auto">
						<table className="w-full text-xs">
							<thead className="text-muted">
								<tr>
									{[
										t("Czas", "Time"),
										t("Żądanie", "Request"),
										t("Kod", "Code"),
										t("Czas odp.", "Time taken"),
										t("Użytkownik", "User"),
										"Trace",
									].map((h) => (
										<th
											key={h}
											className="border-b border-separator px-3 py-2 text-left font-medium"
										>
											{h}
										</th>
									))}
								</tr>
							</thead>
							<tbody>
								{items.map((r) => (
									<tr key={r.id} className="border-b border-separator/60">
										<td className="px-3 py-1.5 whitespace-nowrap">{dateTime(r.at, i18n, true)}</td>
										<td className="px-3 py-1.5 font-mono">
											{r.method} {r.path}
										</td>
										<td className="px-3 py-1.5">
											<Chip size="sm" variant="soft" color={statusTone(r.status)}>
												{r.status}
											</Chip>
										</td>
										<td className="figures px-3 py-1.5 text-right">{r.elapsedMs} ms</td>
										<td className="px-3 py-1.5 font-mono">{r.user ?? "—"}</td>
										<td className="px-3 py-1.5 font-mono text-muted">{r.traceId ?? ""}</td>
									</tr>
								))}
							</tbody>
						</table>
					</div>
					<LoadMore
						noun={t("odpowiedzi", "answers")}
						shown={items.length}
						hasMore={list.hasNextPage}
						isLoading={list.isFetchingNextPage}
						onLoadMore={() => void list.fetchNextPage()}
					/>
				</>
			)}
			{list.isPending ? <Skeleton className="m-4 h-20 rounded-lg" /> : null}
		</Card>
	);
}
