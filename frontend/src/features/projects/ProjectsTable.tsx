import { Table } from "@heroui/react";
import { useNavigate } from "@tanstack/react-router";
import type { ProjectResponse } from "#/api/models";
import { useI18n } from "#/i18n";
import { formatMoney } from "#/lib";
import { DueDate, StageChip } from "./StageChip";

/** Projects in due-date order; a row opens the project. `hide` drops columns that the page already shows. */
export function ProjectsTable({
	projects,
	hide = [],
	label,
}: {
	projects: ProjectResponse[];
	hide?: ("client" | "team" | "owner")[];
	label?: string;
}) {
	const { t } = useI18n();
	const navigate = useNavigate();
	return (
		<Table className="rounded-none shadow-none">
			<Table.ScrollContainer>
				<Table.Content aria-label={label ?? t("Projekty", "Projects")} className="min-w-[880px]">
					<Table.Header>
						<Table.Column isRowHeader>{t("Projekt", "Project")}</Table.Column>
						{hide.includes("client") ? null : <Table.Column>{t("Klient", "Client")}</Table.Column>}
						{hide.includes("team") ? null : <Table.Column>{t("Zespół", "Team")}</Table.Column>}
						<Table.Column>{t("Spółka", "Company")}</Table.Column>
						{hide.includes("owner") ? null : (
							<Table.Column>{t("Właściciel", "Owner")}</Table.Column>
						)}
						<Table.Column>{t("Etap", "Stage")}</Table.Column>
						<Table.Column>{t("Termin", "Due")}</Table.Column>
						<Table.Column className="text-right">{t("Budżet", "Budget")}</Table.Column>
					</Table.Header>
					<Table.Body>
						{projects.map((p) => (
							<Table.Row
								key={p.id}
								id={p.id}
								className="is-clickable"
								onAction={() =>
									void navigate({ to: "/projects/$projectId", params: { projectId: p.id } })
								}
							>
								<Table.Cell>
									<span className="font-medium text-foreground">{p.name}</span>
								</Table.Cell>
								{hide.includes("client") ? null : (
									<Table.Cell>
										<div className="flex flex-col">
											<span>{p.clientName}</span>
											<span className="text-xs text-muted">{p.clientCity ?? ""}</span>
										</div>
									</Table.Cell>
								)}
								{hide.includes("team") ? null : <Table.Cell>{p.teamName}</Table.Cell>}
								<Table.Cell>
									<span className="text-xs">{p.legalEntityName}</span>
								</Table.Cell>
								{hide.includes("owner") ? null : (
									<Table.Cell>
										<span className="font-mono text-xs text-muted">{p.ownerLogin}</span>
									</Table.Cell>
								)}
								<Table.Cell>
									<StageChip stage={p.stage} />
								</Table.Cell>
								<Table.Cell>
									<DueDate date={p.dueDate} overdue={p.overdue} />
								</Table.Cell>
								<Table.Cell className="text-right">
									<span className="figures text-xs">{formatMoney(p.budget)}</span>
								</Table.Cell>
							</Table.Row>
						))}
					</Table.Body>
				</Table.Content>
			</Table.ScrollContainer>
		</Table>
	);
}
