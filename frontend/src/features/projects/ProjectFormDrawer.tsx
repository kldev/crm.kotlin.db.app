import { useStore } from "@tanstack/react-form";
import { useQuery } from "@tanstack/react-query";
import { forwardRef, useImperativeHandle, useMemo, useState } from "react";
import { z } from "zod";
import type { ProjectResponse } from "#/api/models";
import { ApiError, FormDrawer } from "#/components/ui";
import { teamsQuery, useTeamMembers } from "#/features/teams/hooks";
import { useAppForm } from "#/forms";
import { type I18n, useI18n } from "#/i18n";
import { todayIso } from "#/lib";
import { useCreateProject, useUpdateProject } from "./hooks";

export interface ProjectFormCommand {
	create: (client: { id: number; name: string }) => void;
	edit: (project: ProjectResponse) => void;
}

// A factory, so the messages follow the language; the type of the values does not depend on it.
const makeSchema = (t: I18n["t"]) =>
	z
		.object({
			name: z
				.string()
				.trim()
				.min(1, t("Nazwa jest wymagana", "Name is required"))
				.max(200, t("Najwyżej 200 znaków", "At most 200 characters")),
			teamId: z
				.string()
				.min(1, t("Wybierz zespół, który go realizuje", "Choose the team that delivers it")),
			ownerUserId: z.string().min(1, t("Wybierz właściciela", "Choose who owns it")),
			startDate: z.iso.date(t("Wybierz datę rozpoczęcia", "Pick a start date")),
			dueDate: z.iso.date(t("Wybierz termin", "Pick a due date")),
			budget: z
				.string()
				.trim()
				.refine(
					(v) => /^\d+([.,]\d{1,2})?$/.test(v),
					t("Kwota, np. 25000 albo 25000,50", "An amount like 25000 or 25000.50"),
				),
		})
		.refine((v) => v.dueDate >= v.startDate, {
			message: t("Termin jest przed datą rozpoczęcia", "Due date is before the start"),
			path: ["dueDate"],
		});
type Values = z.infer<ReturnType<typeof makeSchema>>;

type Target =
	| { mode: "create"; client: { id: number; name: string } }
	| { mode: "edit"; project: ProjectResponse };

export const ProjectFormDrawer = forwardRef<
	ProjectFormCommand,
	{ onSaved: (project: ProjectResponse, created: boolean) => void }
>(({ onSaved }, ref) => {
	const [target, setTarget] = useState<Target | null>(null);
	useImperativeHandle(
		ref,
		() => ({
			create: (client) => setTarget({ mode: "create", client }),
			edit: (project) => setTarget({ mode: "edit", project }),
		}),
		[],
	);
	if (!target) return null;
	return (
		<FormContent
			target={target}
			onClose={() => setTarget(null)}
			onSaved={(project) => {
				setTarget(null);
				onSaved(project, target.mode === "create");
			}}
		/>
	);
});
ProjectFormDrawer.displayName = "ProjectFormDrawer";

function FormContent({
	target,
	onClose,
	onSaved,
}: {
	target: Target;
	onClose: () => void;
	onSaved: (p: ProjectResponse) => void;
}) {
	const { t } = useI18n();
	const schema = useMemo(() => makeSchema(t), [t]);
	const editing = target.mode === "edit" ? target.project : null;
	const create = useCreateProject(onSaved);
	const update = useUpdateProject(editing?.id ?? 0, onSaved);
	const mutation = editing ? update : create;
	const teams = useQuery(teamsQuery());

	const form = useAppForm({
		defaultValues: {
			name: editing?.name ?? "",
			teamId: editing ? String(editing.teamId) : "",
			ownerUserId: editing ? String(editing.ownerUserId) : "",
			startDate: editing?.startDate ?? todayIso(),
			dueDate: editing?.dueDate ?? "",
			budget: editing ? String(editing.budget) : "",
		} satisfies Values,
		validators: { onChange: schema },
		onSubmit: ({ value }) => {
			const common = {
				name: value.name.trim(),
				teamId: Number(value.teamId),
				ownerUserId: Number(value.ownerUserId),
				startDate: value.startDate,
				dueDate: value.dueDate,
				budget: Number(value.budget.replace(",", ".")),
			};
			if (editing) update.mutate({ ...common, rowVersion: editing.rowVersion });
			else if (target.mode === "create") create.mutate({ ...common, clientId: target.client.id });
		},
	});

	const teamId = useStore(form.store, (state) => state.values.teamId);
	const members = useTeamMembers(teamId ? Number(teamId) : undefined);

	return (
		<FormDrawer
			title={editing ? t("Edycja projektu", "Edit project") : t("Nowy projekt", "New project")}
			description={
				editing
					? editing.name
					: `${t("Dla", "For")} ${target.mode === "create" ? target.client.name : ""}`
			}
			onClose={onClose}
			onSubmit={() => void form.handleSubmit()}
		>
			<FormDrawer.Body>
				<form.AppField name="name">
					{(f) => (
						<f.FormInput
							label={t("Nazwa projektu", "Project name")}
							placeholder={t("Wdrożenie CRM", "CRM rollout")}
							autoFocus
						/>
					)}
				</form.AppField>
				<form.AppField
					name="teamId"
					listeners={{ onChange: () => form.setFieldValue("ownerUserId", "") }}
				>
					{(f) => (
						<f.FormSelect
							label={t("Zespół realizujący", "Delivering team")}
							placeholder={
								teams.isPending
									? t("Wczytywanie zespołów…", "Loading teams…")
									: t("Wybierz zespół", "Choose a team")
							}
							options={(teams.data ?? []).map((team) => ({
								id: String(team.id),
								label: team.name,
								description: t(
									`Lider ${team.leadLogin} · członków: ${team.memberCount}`,
									`Lead ${team.leadLogin} · ${team.memberCount} members`,
								),
							}))}
						/>
					)}
				</form.AppField>
				<form.AppField name="ownerUserId">
					{(f) => (
						<f.FormSelect
							label={t("Właściciel", "Owner")}
							isDisabled={!teamId}
							placeholder={
								!teamId
									? t("Najpierw wybierz zespół", "Choose the team first")
									: members.isPending
										? t("Wczytywanie członków…", "Loading members…")
										: t("Wybierz członka zespołu", "Choose a member")
							}
							options={(members.data ?? [])
								.filter((m) => m.active)
								.map((m) => ({ id: String(m.userId), label: m.displayName, description: m.login }))}
							// Rule 51037 of the procedures: the owner is an active member of the project team.
							description={t(
								"Właścicielem projektu może być tylko aktywny członek zespołu.",
								"Only active members of the team can own its projects.",
							)}
						/>
					)}
				</form.AppField>
				<div className="grid grid-cols-2 gap-4">
					<form.AppField name="startDate">
						{(f) => <f.FormInput label={t("Rozpoczęcie", "Start")} type="date" />}
					</form.AppField>
					<form.AppField name="dueDate">
						{(f) => <f.FormInput label={t("Termin", "Due")} type="date" />}
					</form.AppField>
				</div>
				<form.AppField name="budget">
					{(f) => (
						<f.FormInput
							label={t("Budżet (PLN)", "Budget (PLN)")}
							placeholder="25000"
							inputMode="decimal"
						/>
					)}
				</form.AppField>
				<ApiError error={mutation.error} />
			</FormDrawer.Body>
			<FormDrawer.Footer
				submitLabel={
					editing ? t("Zapisz zmiany", "Save changes") : t("Dodaj projekt", "Create project")
				}
				isPending={mutation.isPending}
			/>
		</FormDrawer>
	);
}
