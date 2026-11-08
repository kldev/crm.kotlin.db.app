import { Button, Card, Chip, Table } from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { Landmark, Plus } from "lucide-react";
import { useRef } from "react";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError, EmptyState, TableSkeleton } from "#/components/ui";
import { useMe } from "#/features/auth/session";
import { useI18n } from "#/i18n";
import { type CompanyCommand, CompanyDrawer } from "./CompanyDrawer";
import { legalEntitiesQuery } from "./hooks";

/** NIP as people write it: 525-000-00-15. */
export const formatNip = (nip: string) =>
	`${nip.slice(0, 3)}-${nip.slice(3, 6)}-${nip.slice(6, 8)}-${nip.slice(8)}`;

/**
 * The group's own companies (ADR-0016) - they deliver the projects and sign the offers. Everybody sees them, an
 * administrator adds and changes them; a closed company stays for its history.
 */
export function CompaniesPage() {
	const { t, locale } = useI18n();
	const me = useMe();
	const admin = me.role === "ADMIN";
	const drawer = useRef<CompanyCommand>(null);
	const query = useQuery(legalEntitiesQuery());
	const date = (iso: string) =>
		new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(new Date(`${iso}T00:00:00`));
	return (
		<>
			<PageHeader
				eyebrow="CRM"
				title={t("Spółki", "Companies")}
				description={t(
					"Spółki grupy, które realizują projekty i podpisują oferty. Nie mylić z klientami.",
					"The group's companies that deliver projects and sign offers. Not the clients.",
				)}
				actions={
					admin ? (
						<Button onPress={() => drawer.current?.create()}>
							<Plus className="size-4" />
							{t("Nowa spółka", "New company")}
						</Button>
					) : null
				}
			/>
			<Card className="overflow-hidden p-0">
				{query.isPending ? (
					<TableSkeleton rows={4} />
				) : query.isError ? (
					<div className="p-4">
						<ApiError error={query.error} />
					</div>
				) : query.data.length === 0 ? (
					<EmptyState icon={Landmark} title={t("Brak spółek", "No companies")} />
				) : (
					<Table className="rounded-none shadow-none">
						<Table.ScrollContainer>
							<Table.Content aria-label={t("Spółki", "Companies")} className="min-w-[900px]">
								<Table.Header>
									<Table.Column isRowHeader>{t("Spółka", "Company")}</Table.Column>
									<Table.Column>NIP</Table.Column>
									<Table.Column>{t("Adres", "Address")}</Table.Column>
									<Table.Column>{t("Kontakt", "Contact")}</Table.Column>
									<Table.Column>{t("Działa", "Trades")}</Table.Column>
									<Table.Column className="text-right">{t("Oferty", "Offers")}</Table.Column>
								</Table.Header>
								<Table.Body>
									{query.data.map((e) => (
										<Table.Row
											key={e.id}
											id={e.id}
											className={admin ? "is-clickable" : undefined}
											onAction={admin ? () => drawer.current?.edit(e) : undefined}
										>
											<Table.Cell>
												<div className="flex flex-col">
													<span className="font-medium text-foreground">{e.name}</span>
													<span className="text-xs text-muted">{e.legalName}</span>
												</div>
											</Table.Cell>
											<Table.Cell>
												<span className="font-mono text-xs">{formatNip(e.taxId)}</span>
											</Table.Cell>
											<Table.Cell>
												<span className="text-xs">{e.address}</span>
											</Table.Cell>
											<Table.Cell>
												<div className="flex flex-col text-xs">
													<span>{e.phone ?? ""}</span>
													<span className="text-muted">{e.email ?? ""}</span>
												</div>
											</Table.Cell>
											<Table.Cell>
												<div className="flex flex-col items-start gap-1">
													<Chip size="sm" variant="soft" color={e.trading ? "success" : "default"}>
														{e.trading ? t("Działa", "Trading") : t("Zamknięta", "Closed")}
													</Chip>
													<span className="text-[11px] text-muted">
														{t("od", "from")} {date(e.activeFrom)}
														{e.activeTo ? ` ${t("do", "to")} ${date(e.activeTo)}` : ""}
													</span>
												</div>
											</Table.Cell>
											<Table.Cell className="text-right">
												<span className="figures text-xs">{e.offers}</span>
											</Table.Cell>
										</Table.Row>
									))}
								</Table.Body>
							</Table.Content>
						</Table.ScrollContainer>
					</Table>
				)}
			</Card>
			<CompanyDrawer ref={drawer} />
		</>
	);
}
