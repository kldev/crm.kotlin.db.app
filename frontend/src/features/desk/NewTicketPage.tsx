import { Card, Skeleton, toast } from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError } from "#/components/ui";
import { useI18n } from "#/i18n";
import { ReportForm } from "./components/ReportForm";
import { deskCatalogQuery, peopleQuery, useReportTicket } from "./hooks";

/** An agent registers a ticket taken by phone or e-mail; it may be dated back up to 30 days. */
export function NewTicketPage() {
	const { t } = useI18n();
	const navigate = useNavigate();
	const catalog = useQuery(deskCatalogQuery());
	const people = useQuery(peopleQuery());
	const report = useReportTicket((ticket) => {
		toast.success(t(`Zarejestrowano ${ticket.number}`, `Registered ${ticket.number}`));
		void navigate({ to: "/desk/tickets/$ticketId", params: { ticketId: ticket.id } });
	});

	return (
		<>
			<PageHeader
				eyebrow={t("Service desk", "Service desk")}
				title={t("Nowe zgłoszenie", "New ticket")}
				description={t(
					"Sprawa zgłoszona telefonicznie albo mailem. Trafi do puli.",
					"A request made by phone or e-mail. It goes to the pool.",
				)}
			/>
			<Card>
				<Card.Content className="p-2 sm:p-4">
					{catalog.isPending || people.isPending ? (
						<Skeleton className="h-96 w-full rounded-xl" />
					) : catalog.isError || people.isError ? (
						<ApiError error={catalog.error ?? people.error} />
					) : (
						<ReportForm
							mode="agent"
							catalog={catalog.data}
							people={people.data}
							isPending={report.isPending}
							error={report.error}
							onSubmit={(v) =>
								report.mutate({
									title: v.title.trim(),
									description: v.description.trim(),
									categoryKey: v.categoryKey,
									subcategoryKey: v.subcategoryKey,
									priority: v.priority,
									// datetime-local is the browser's time; Date turns it into the instant.
									reportedAt: new Date(v.reportedAt).toISOString(),
									requesterPersonId: v.requesterPersonId,
									requesterIncognito: v.requesterIncognito,
								})
							}
						/>
					)}
				</Card.Content>
			</Card>
		</>
	);
}
