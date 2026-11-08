import { forwardRef, useImperativeHandle, useMemo, useState } from "react";
import { z } from "zod";
import type { TeamResponse } from "#/api/models";
import { ApiError, FormDrawer } from "#/components/ui";
import { useManagers } from "#/features/users/hooks";
import { useAppForm } from "#/forms";
import { type I18n, useI18n } from "#/i18n";
import { useCreateTeam } from "./hooks";

export interface CreateTeamCommand {
	open: () => void;
}

// A factory, so the messages follow the language.
const makeSchema = (t: I18n["t"]) =>
	z.object({
		name: z
			.string()
			.trim()
			.min(1, t("Nazwa jest wymagana", "Name is required"))
			.max(200, t("Najwyżej 200 znaków", "At most 200 characters")),
		leadUserId: z.string().min(1, t("Wybierz lidera", "Choose the lead")),
	});

export const CreateTeamDrawer = forwardRef<
	CreateTeamCommand,
	{ onCreated: (t: TeamResponse) => void }
>(({ onCreated }, ref) => {
	const [open, setOpen] = useState(false);
	useImperativeHandle(ref, () => ({ open: () => setOpen(true) }), []);
	if (!open) return null;
	return (
		<FormContent
			onClose={() => setOpen(false)}
			onCreated={(t) => {
				setOpen(false);
				onCreated(t);
			}}
		/>
	);
});
CreateTeamDrawer.displayName = "CreateTeamDrawer";

function FormContent({
	onClose,
	onCreated,
}: {
	onClose: () => void;
	onCreated: (t: TeamResponse) => void;
}) {
	const { t } = useI18n();
	const schema = useMemo(() => makeSchema(t), [t]);
	const managers = useManagers(true);
	const mutation = useCreateTeam(onCreated);
	const form = useAppForm({
		defaultValues: { name: "", leadUserId: "" },
		validators: { onChange: schema },
		onSubmit: ({ value }) =>
			mutation.mutate({ name: value.name.trim(), leadUserId: Number(value.leadUserId) }),
	});
	return (
		<FormDrawer
			title={t("Nowy zespół", "New team")}
			description={t("Prowadzony przez aktywnego managera.", "Led by an active manager.")}
			onClose={onClose}
			onSubmit={() => void form.handleSubmit()}
		>
			<FormDrawer.Body>
				<form.AppField name="name">
					{(f) => (
						<f.FormInput
							label={t("Nazwa zespołu", "Team name")}
							placeholder={t("Północ", "North")}
							autoFocus
						/>
					)}
				</form.AppField>
				<form.AppField name="leadUserId">
					{(f) => (
						<f.FormSelect
							label={t("Lider", "Lead")}
							placeholder={
								managers.isPending
									? t("Wczytywanie managerów…", "Loading managers…")
									: t("Wybierz managera", "Choose a manager")
							}
							options={(managers.data ?? []).map((m) => ({
								id: String(m.id),
								label: m.displayName,
								description: m.login,
							}))}
						/>
					)}
				</form.AppField>
				<ApiError error={mutation.error} />
			</FormDrawer.Body>
			<FormDrawer.Footer
				submitLabel={t("Utwórz zespół", "Create team")}
				isPending={mutation.isPending}
			/>
		</FormDrawer>
	);
}
