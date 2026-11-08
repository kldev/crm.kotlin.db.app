import { Card, Chip, SearchField, Skeleton } from "@heroui/react";
import { useInfiniteQuery } from "@tanstack/react-query";
import { useState } from "react";
import { listLogEntries } from "#/api/endpoints/system/system";
import type { PageResponseLogEntry } from "#/api/models";
import { systemKeys } from "#/api/query-keys";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError, LoadMore, SelectFilter } from "#/components/ui";
import { useDebouncedValue } from "#/hooks/useDebouncedValue";
import { useI18n } from "#/i18n";
import { dateTime } from "./format";

/** The application's log from INFO up (ADR-0012), newest first; an exception opens under its entry. */
export function LogsPage() {
	const i18n = useI18n();
	const { t } = i18n;
	const [level, setLevel] = useState<string | undefined>();
	const [text, setText] = useState("");
	const search = useDebouncedValue(text.trim(), 300) || undefined;
	const filters = { level, search };
	const list = useInfiniteQuery({
		queryKey: systemKeys.logs(filters),
		queryFn: ({ pageParam }) => listLogEntries({ ...filters, cursor: pageParam, size: 50 }),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (page: PageResponseLogEntry) => page.nextCursor ?? undefined,
		refetchInterval: 30_000,
	});
	const items = list.data?.pages.flatMap((p) => p.items) ?? [];
	const tone = (l: string) => (l === "ERROR" ? "danger" : l === "WARN" ? "warning" : "default");
	return (
		<>
			<PageHeader
				eyebrow={t("System", "System")}
				title={t("Logi", "Logs")}
				description={t("Log aplikacji od poziomu INFO.", "The application log from INFO up.")}
			/>
			<Card className="overflow-hidden p-0">
				<div className="flex flex-col gap-3 border-b border-separator p-4 sm:flex-row sm:items-center">
					<SelectFilter
						label={t("Poziom od", "Level from")}
						value={level}
						options={["INFO", "WARN", "ERROR"].map((l) => ({ id: l, label: l }))}
						onChange={setLevel}
					/>
					<SearchField
						aria-label={t("Szukaj", "Search")}
						className="w-full sm:max-w-sm"
						value={text}
						onChange={setText}
					>
						<SearchField.Group>
							<SearchField.SearchIcon />
							<SearchField.Input
								placeholder={t("W treści albo źródle…", "In the message or the source…")}
							/>
							<SearchField.ClearButton />
						</SearchField.Group>
					</SearchField>
				</div>
				{list.isPending ? (
					<Skeleton className="m-4 h-40 rounded-lg" />
				) : list.isError ? (
					<div className="p-4">
						<ApiError error={list.error} />
					</div>
				) : (
					<>
						<ul className="divide-y divide-separator">
							{items.map((e) => (
								<li key={e.id} className="flex flex-col gap-1 px-4 py-2 text-xs">
									<div className="flex flex-wrap items-center gap-2">
										<Chip size="sm" variant="soft" color={tone(e.level)}>
											{e.level}
										</Chip>
										<span className="text-muted">{dateTime(e.at, i18n, true)}</span>
										<span className="font-mono text-muted">{e.source}</span>
										{e.requestPath ? (
											<span className="font-mono text-muted">{e.requestPath}</span>
										) : null}
									</div>
									<p className="text-sm whitespace-pre-wrap text-foreground">{e.message}</p>
									{e.exception ? (
										<details>
											<summary className="cursor-pointer text-muted">
												{t("Wyjątek", "Exception")}
											</summary>
											<pre className="mt-1 max-h-80 overflow-auto rounded-md bg-surface-secondary p-2 text-[11px]">
												{e.exception}
											</pre>
										</details>
									) : null}
								</li>
							))}
						</ul>
						<LoadMore
							noun={t("wpisów", "entries")}
							shown={items.length}
							hasMore={list.hasNextPage}
							isLoading={list.isFetchingNextPage}
							onLoadMore={() => void list.fetchNextPage()}
						/>
					</>
				)}
			</Card>
		</>
	);
}
