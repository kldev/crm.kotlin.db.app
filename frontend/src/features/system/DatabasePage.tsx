import { Card, Chip, Skeleton } from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { AlarmClock } from "lucide-react";
import { getDatabaseState } from "#/api/endpoints/system/system";
import { systemKeys } from "#/api/query-keys";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError } from "#/components/ui";
import { DataTable, StatTile } from "#/features/desk/charts/ChartKit";
import { useI18n } from "#/i18n";
import { dateTime } from "./format";

/**
 * The database (ADR-0012): server and size, sessions now with blocking marked, tables by size, and the desk's event
 * store. Read through procedures signed with a certificate - the application login holds no server permission.
 */
export function DatabasePage() {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const db = useQuery({
		queryKey: systemKeys.database(),
		queryFn: () => getDatabaseState(),
		refetchInterval: 30_000,
	});
	return (
		<>
			<PageHeader
				eyebrow={t("System", "System")}
				title={t("Baza danych", "Database")}
				description="SQL Server"
			/>
			{db.isPending ? (
				<Skeleton className="h-96 w-full rounded-xl" />
			) : db.isError ? (
				<ApiError error={db.error} />
			) : (
				(() => {
					const o = db.data.overview;
					return (
						<div className="flex flex-col gap-6">
							<div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-6">
								<StatTile label={t("Serwer", "Server")} value={o.productVersion} note={o.edition} />
								<StatTile label={t("Uruchomiony", "Started")} value={dateTime(o.startedAt, i18n)} />
								<StatTile
									label={t("Dane / log", "Data / log")}
									value={`${o.dataMb ?? "—"} MB`}
									note={`log ${o.logMb ?? "—"} MB`}
								/>
								<StatTile
									label={t("Sesje / zapytania", "Sessions / requests")}
									value={`${o.userSessions ?? "—"} / ${o.activeRequests ?? "—"}`}
									icon={AlarmClock}
									tone={(o.blockedRequests ?? 0) > 0 ? "danger" : undefined}
									note={t(
										`zablokowane: ${o.blockedRequests ?? 0}`,
										`blocked: ${o.blockedRequests ?? 0}`,
									)}
								/>
								<StatTile
									label={t("Zdarzenia zgłoszeń", "Ticket events")}
									value={o.events.toLocaleString(locale)}
									note={t(
										`ostatnie: ${dateTime(o.lastEventAt, i18n)}`,
										`last: ${dateTime(o.lastEventAt, i18n)}`,
									)}
								/>
								<StatTile
									label={t("Zgłoszenia", "Tickets")}
									value={o.tickets.toLocaleString(locale)}
									note={`seq ${o.lastEventSeq ?? "—"}`}
								/>
							</div>
							<Card>
								<Card.Header>
									<Card.Title>{t("Sesje", "Sessions")}</Card.Title>
									<Card.Description>
										{t("Blokujące i zablokowane na górze.", "Blocking and blocked ones on top.")}
									</Card.Description>
								</Card.Header>
								<Card.Content className="overflow-x-auto">
									<table className="w-full text-xs">
										<thead className="text-muted">
											<tr>
												{[
													"ID",
													t("Login", "Login"),
													t("Program", "Program"),
													t("Stan", "State"),
													t("Polecenie", "Command"),
													t("Czeka na", "Waits for"),
													t("Blokuje / blokowana", "Blocks / blocked by"),
													t("Czas", "Elapsed"),
													"SQL",
												].map((h) => (
													<th
														key={h}
														className="border-b border-separator px-2 py-1.5 text-left font-medium"
													>
														{h}
													</th>
												))}
											</tr>
										</thead>
										<tbody>
											{db.data.sessions.map((s) => (
												<tr
													key={s.sessionId}
													className={`border-b border-separator/60 align-top ${s.blockingSessionId || s.blocking ? "bg-danger-soft/40" : ""}`}
												>
													<td className="px-2 py-1.5 font-mono">{s.sessionId}</td>
													<td className="px-2 py-1.5">{s.login}</td>
													<td className="max-w-48 truncate px-2 py-1.5" title={s.program ?? ""}>
														{s.program}
													</td>
													<td className="px-2 py-1.5">{s.requestStatus ?? s.sessionStatus}</td>
													<td className="px-2 py-1.5">{s.command ?? ""}</td>
													<td className="px-2 py-1.5">
														{s.waitType ? `${s.waitType} (${s.waitMs} ms)` : ""}
													</td>
													<td className="px-2 py-1.5">
														{s.blocking ? (
															<Chip size="sm" variant="soft" color="danger">
																{t("blokuje", "blocking")}
															</Chip>
														) : null}
														{s.blockingSessionId ? `← ${s.blockingSessionId}` : ""}
													</td>
													<td className="figures px-2 py-1.5 text-right">
														{s.elapsedMs != null ? `${s.elapsedMs} ms` : ""}
													</td>
													<td className="max-w-96 px-2 py-1.5 font-mono text-[11px] break-all text-muted">
														{s.sqlText ?? ""}
													</td>
												</tr>
											))}
										</tbody>
									</table>
								</Card.Content>
							</Card>
							<Card>
								<Card.Header>
									<Card.Title>{t("Tabele", "Tables")}</Card.Title>
								</Card.Header>
								<Card.Content>
									<DataTable
										head={[
											t("Tabela", "Table"),
											t("Wiersze", "Rows"),
											t("Zajęte MB", "Reserved MB"),
											t("Dane MB", "Data MB"),
											t("Indeksy MB", "Indexes MB"),
										]}
										rows={db.data.tables.map((x) => [
											`${x.schema}.${x.table}`,
											x.rows,
											Math.round(x.reservedMb * 10) / 10,
											Math.round(x.dataMb * 10) / 10,
											Math.round(x.indexMb * 10) / 10,
										])}
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
