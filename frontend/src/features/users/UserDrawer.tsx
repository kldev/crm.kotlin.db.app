import { toast } from "@heroui/react";
import { forwardRef, useImperativeHandle, useMemo, useState } from "react";
import { z } from "zod";
import type { UserResponse } from "#/api/models";
import { ApiError, FormDrawer } from "#/components/ui";
import { ROLES, roleLabel } from "#/features/types";
import { useAppForm } from "#/forms";
import { type I18n, useI18n } from "#/i18n";
import { useChangeUserRole, useCreateUser, useResetUserPassword } from "./hooks";

export interface UserDrawerCommand {
	create: () => void;
	edit: (user: UserResponse) => void;
	resetPassword: (user: UserResponse) => void;
}

type Target =
	| { mode: "create" }
	| { mode: "role"; user: UserResponse }
	| { mode: "password"; user: UserResponse };

const useRoleOptions = () => {
	const i18n = useI18n();
	return ROLES.map((r) => ({ id: r, label: roleLabel(r, i18n) }));
};

const passwordRule = (t: I18n["t"]) =>
	z.string().min(8, t("Co najmniej 8 znaków", "At least 8 characters"));

export const UserDrawer = forwardRef<UserDrawerCommand>((_props, ref) => {
	const [target, setTarget] = useState<Target | null>(null);
	useImperativeHandle(
		ref,
		() => ({
			create: () => setTarget({ mode: "create" }),
			edit: (user) => setTarget({ mode: "role", user }),
			resetPassword: (user) => setTarget({ mode: "password", user }),
		}),
		[],
	);
	if (!target) return null;
	const close = () => setTarget(null);
	if (target.mode === "create") return <CreateUser onClose={close} />;
	if (target.mode === "role") return <ChangeRole user={target.user} onClose={close} />;
	return <ResetPassword user={target.user} onClose={close} />;
});
UserDrawer.displayName = "UserDrawer";

// A factory, so the messages follow the language.
const makeCreateSchema = (t: I18n["t"]) =>
	z.object({
		login: z
			.string()
			.trim()
			.regex(
				/^[a-z0-9._-]{3,64}$/,
				t(
					"3-64 znaki: małe litery, cyfry, kropka, podkreślenie, łącznik",
					"3-64 characters: lowercase letters, digits, dot, underscore, hyphen",
				),
			),
		displayName: z
			.string()
			.trim()
			.min(1, t("Imię i nazwisko jest wymagane", "Display name is required"))
			.max(200, t("Najwyżej 200 znaków", "At most 200 characters")),
		role: z.enum(ROLES),
		password: passwordRule(t),
	});

function CreateUser({ onClose }: { onClose: () => void }) {
	const { t } = useI18n();
	const roleOptions = useRoleOptions();
	const createSchema = useMemo(() => makeCreateSchema(t), [t]);
	const mutation = useCreateUser((u) => {
		toast.success(t(`Dodano użytkownika ${u.login}`, `User ${u.login} created`));
		onClose();
	});
	const form = useAppForm({
		defaultValues: {
			login: "",
			displayName: "",
			role: "SALES" as (typeof ROLES)[number],
			password: "",
		},
		validators: { onChange: createSchema },
		onSubmit: ({ value }) => mutation.mutate(value),
	});
	return (
		<FormDrawer
			title={t("Nowy użytkownik", "New user")}
			onClose={onClose}
			onSubmit={() => void form.handleSubmit()}
		>
			<FormDrawer.Body>
				<form.AppField name="login">
					{(f) => <f.FormInput label={t("Login", "Login")} placeholder="anna.nowak" autoFocus />}
				</form.AppField>
				<form.AppField name="displayName">
					{(f) => (
						<f.FormInput label={t("Imię i nazwisko", "Display name")} placeholder="Anna Nowak" />
					)}
				</form.AppField>
				<form.AppField name="role">
					{(f) => <f.FormSelect label={t("Rola", "Role")} options={roleOptions} />}
				</form.AppField>
				<form.AppField name="password">
					{(f) => (
						<f.FormInput
							label={t("Hasło początkowe", "Initial password")}
							type="password"
							autoComplete="new-password"
							description={t(
								"Użytkownik może je zmienić po zalogowaniu.",
								"The user can change it after signing in.",
							)}
						/>
					)}
				</form.AppField>
				<ApiError error={mutation.error} />
			</FormDrawer.Body>
			<FormDrawer.Footer
				submitLabel={t("Dodaj użytkownika", "Create user")}
				isPending={mutation.isPending}
			/>
		</FormDrawer>
	);
}

function ChangeRole({ user, onClose }: { user: UserResponse; onClose: () => void }) {
	const i18n = useI18n();
	const { t } = i18n;
	const roleOptions = useRoleOptions();
	const mutation = useChangeUserRole((u) => {
		const role = roleLabel(u.role, i18n);
		toast.success(t(`${u.displayName} - nowa rola: ${role}`, `${u.displayName} is now ${role}`));
		onClose();
	});
	const form = useAppForm({
		defaultValues: { role: user.role as (typeof ROLES)[number] },
		validators: { onChange: z.object({ role: z.enum(ROLES) }) },
		onSubmit: ({ value }) => mutation.mutate({ id: user.id, role: value.role }),
	});
	return (
		<FormDrawer
			title={t("Zmiana roli", "Change role")}
			description={`${user.displayName} · ${user.login}`}
			onClose={onClose}
			onSubmit={() => void form.handleSubmit()}
		>
			<FormDrawer.Body>
				<form.AppField name="role">
					{(f) => <f.FormSelect label={t("Rola", "Role")} options={roleOptions} />}
				</form.AppField>
				<ApiError error={mutation.error} />
			</FormDrawer.Body>
			<FormDrawer.Footer isPending={mutation.isPending} />
		</FormDrawer>
	);
}

function ResetPassword({ user, onClose }: { user: UserResponse; onClose: () => void }) {
	const { t } = useI18n();
	const mutation = useResetUserPassword(() => {
		toast.success(
			t(
				`Ustawiono hasło ${user.login}; konto jest odblokowane`,
				`Password of ${user.login} set; the account is unlocked`,
			),
		);
		onClose();
	});
	const form = useAppForm({
		defaultValues: { password: "" },
		validators: { onChange: z.object({ password: passwordRule(t) }) },
		onSubmit: ({ value }) => mutation.mutate({ id: user.id, password: value.password }),
	});
	return (
		<FormDrawer
			title={t("Ustaw hasło", "Set password")}
			description={`${user.displayName} · ${user.login}`}
			onClose={onClose}
			onSubmit={() => void form.handleSubmit()}
		>
			<FormDrawer.Body>
				<form.AppField name="password">
					{(f) => (
						<f.FormInput
							label={t("Nowe hasło", "New password")}
							type="password"
							autoComplete="new-password"
							autoFocus
						/>
					)}
				</form.AppField>
				<ApiError error={mutation.error} />
			</FormDrawer.Body>
			<FormDrawer.Footer
				submitLabel={t("Ustaw hasło", "Set password")}
				isPending={mutation.isPending}
			/>
		</FormDrawer>
	);
}
