import { Button, Card, Chip } from "@heroui/react";
import { useInfiniteQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { Plus } from "lucide-react";
import { ApiError, LoadMore } from "#/components/ui";
import { useI18n } from "#/i18n";
import { offersQuery } from "./hooks";
import { money, type OfferStatus, offerStatusColor, offerStatusLabel, templateName } from "./types";

/** The offers of one client on the client's page, newest first, with "new offer" for this client. */
export function ClientOffers({ clientId, onNew }: { clientId: number; onNew: () => void }) {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const query = useInfiniteQuery(offersQuery({ clientId }, 10));
	const offers = query.data?.pages.flatMap((p) => p.items) ?? [];
	return (
		<Card className="mt-6 overflow-hidden p-0">
			<div className="flex items-center justify-between gap-3 border-b border-separator p-4">
				<span className="font-display text-xl font-semibold">{t("Oferty", "Offers")}</span>
				<Button size="sm" onPress={onNew}>
					<Plus className="size-4" />
					{t("Nowa oferta", "New offer")}
				</Button>
			</div>
			{query.isError ? (
				<div className="p-4">
					<ApiError error={query.error} />
				</div>
			) : offers.length === 0 && !query.isPending ? (
				<p className="p-4 text-sm text-muted">
					{t("Brak ofert dla tego klienta.", "No offers for this client.")}
				</p>
			) : (
				<>
					<ul className="divide-y divide-separator">
						{offers.map((o) => (
							<li
								key={o.id}
								className="flex flex-wrap items-center justify-between gap-3 px-4 py-3 text-sm"
							>
								<Link
									to="/offers/$offerId"
									params={{ offerId: o.id }}
									className="flex min-w-0 flex-col hover:underline"
								>
									<span className="font-medium">{o.title}</span>
									<span className="font-mono text-[11px] text-muted">
										{o.number} · {templateName(o, i18n)}
									</span>
								</Link>
								<span className="flex items-center gap-3">
									<Chip
										size="sm"
										variant="soft"
										color={offerStatusColor[o.status as OfferStatus] ?? "default"}
									>
										{offerStatusLabel(o.status, i18n)}
									</Chip>
									<span className="figures">{money(o.totalGross, o.currency, locale)}</span>
								</span>
							</li>
						))}
					</ul>
					{offers.length > 0 ? (
						<LoadMore
							noun={t("ofert", "offers")}
							shown={offers.length}
							hasMore={query.hasNextPage}
							isLoading={query.isFetchingNextPage}
							onLoadMore={() => void query.fetchNextPage()}
						/>
					) : null}
				</>
			)}
		</Card>
	);
}
