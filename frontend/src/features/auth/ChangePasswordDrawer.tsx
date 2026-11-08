import { useMutation } from "@tanstack/react-query";
import { forwardRef, useImperativeHandle, useMemo, useState } from "react";
import { z } from "zod";
import { changeOwnPassword } from "#/api/endpoints/auth/auth";
import { ApiError, FormDrawer } from "#/components/ui";
import { useAppForm } from "#/forms";
import { type I18n, useI18n } from "#/i18n";

export interface ChangePasswordCommand {
	open: () => void;
}

// A factory, so the messages follow the language; the type of the values does not depend on it.
const makeSchema = (t: I18n["t"]) =>
	z
		.object({
			currentPassword: z.string().min(1, t("Podaj obecne hasło", "Enter your current password")),
			newPassword: z.string().min(8, t("Co najmniej 8 znaków", "At least 8 characters")),
			repeat: z.string(),
		})
		.refine((v) => v.newPassword === v.repeat, {
			message: t("Hasła się różnią", "Passwords differ"),
			path: ["repeat"],
		});
type Values = z.infer<ReturnType<typeof makeSchema>>;

export const ChangePasswordDrawer = forwardRef<ChangePasswordCommand, { onSuccess: () => void }>(
	({ onSuccess }, ref) => {
		const [open, setOpen] = useState(false);
		useImperativeHandle(ref, () => ({ open: () => setOpen(true) }), []);
		if (!open) return null;
		return (
			<FormContent
				onClose={() => setOpen(false)}
				onSuccess={() => {
					setOpen(false);
					onSuccess();
				}}
			/>
		);
	},
);
ChangePasswordDrawer.displayName = "ChangePasswordDrawer";

function FormContent({ onClose, onSuccess }: { onClose: () => void; onSuccess: () => void }) {
	const { t } = useI18n();
	const schema = useMemo(() => makeSchema(t), [t]);
	const mutation = useMutation({
		mutationFn: (v: Values) =>
			changeOwnPassword({ currentPassword: v.currentPassword, newPassword: v.newPassword }),
		onSuccess,
	});
	const form = useAppForm({
		defaultValues: { currentPassword: "", newPassword: "", repeat: "" },
		validators: { onChange: schema },
		onSubmit: ({ value }) => mutation.mutate(value),
	});

	return (
		<FormDrawer
			title={t("Zmiana hasła", "Change password")}
			onClose={onClose}
			onSubmit={() => void form.handleSubmit()}
		>
			<FormDrawer.Body>
				<form.AppField name="currentPassword">
					{(f) => (
						<f.FormInput
							label={t("Obecne hasło", "Current password")}
							type="password"
							autoComplete="current-password"
							autoFocus
						/>
					)}
				</form.AppField>
				<form.AppField name="newPassword">
					{(f) => (
						<f.FormInput
							label={t("Nowe hasło", "New password")}
							type="password"
							autoComplete="new-password"
							description={t("Co najmniej 8 znaków.", "At least 8 characters.")}
						/>
					)}
				</form.AppField>
				<form.AppField name="repeat">
					{(f) => (
						<f.FormInput
							label={t("Powtórz nowe hasło", "Repeat new password")}
							type="password"
							autoComplete="new-password"
						/>
					)}
				</form.AppField>
				<ApiError error={mutation.error} />
			</FormDrawer.Body>
			<FormDrawer.Footer
				submitLabel={t("Zmień hasło", "Change password")}
				isPending={mutation.isPending}
			/>
		</FormDrawer>
	);
}
