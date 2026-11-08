import { forwardRef, useImperativeHandle, useMemo, useState } from "react";
import { z } from "zod";
import type { ClientResponse } from "#/api/models";
import { ApiError, FormDrawer } from "#/components/ui";
import { can, useMe } from "#/features/auth/session";
import { CITIES, CLIENT_STATUSES, clientStatusLabel } from "#/features/types";
import { useSalesUsers } from "#/features/users/hooks";
import { useAppForm } from "#/forms";
import { type I18n, useI18n } from "#/i18n";
import { useCreateClient, useUpdateClient } from "./hooks";

export interface ClientFormCommand {
	create: () => void;
	edit: (client: ClientResponse) => void;
}

// A factory, so the messages follow the language; the type of the values does not depend on it.
const makeSchema = (t: I18n["t"]) =>
	z.object({
		name: z
			.string()
			.trim()
			.min(1, t("Nazwa jest wymagana", "Name is required"))
			.max(200, t("Najwyżej 200 znaków", "At most 200 characters")),
		nip: z
			.string()
			.trim()
			.refine(
				(v) => v === "" || /^\d{10}$/.test(v.replace(/[\s-]/g, "")),
				t("NIP ma 10 cyfr", "NIP has 10 digits"),
			),
		email: z
			.string()
			.trim()
			.refine(
				(v) => v === "" || z.email().safeParse(v).success,
				t("Nieprawidłowy adres e-mail", "Not a valid e-mail"),
			),
		phone: z.string().trim().max(30, t("Najwyżej 30 znaków", "At most 30 characters")),
		city: z.string().trim().max(100, t("Najwyżej 100 znaków", "At most 100 characters")),
		status: z.enum(CLIENT_STATUSES),
		assignedUserId: z.string(),
		note: z.string().max(2000, t("Najwyżej 2000 znaków", "At most 2000 characters")),
	});
type Values = z.infer<ReturnType<typeof makeSchema>>;

const orNull = (v: string) => (v.trim() === "" ? null : v.trim());

type Target = { mode: "create" } | { mode: "edit"; client: ClientResponse };

export const ClientFormDrawer = forwardRef<
	ClientFormCommand,
	{ onSaved: (client: ClientResponse, created: boolean) => void }
>(({ onSaved }, ref) => {
	const [target, setTarget] = useState<Target | null>(null);
	useImperativeHandle(
		ref,
		() => ({
			create: () => setTarget({ mode: "create" }),
			edit: (client) => setTarget({ mode: "edit", client }),
		}),
		[],
	);
	if (!target) return null;
	return (
		<FormContent
			target={target}
			onClose={() => setTarget(null)}
			onSaved={(client) => {
				setTarget(null);
				onSaved(client, target.mode === "create");
			}}
		/>
	);
});
ClientFormDrawer.displayName = "ClientFormDrawer";

function FormContent({
	target,
	onClose,
	onSaved,
}: {
	target: Target;
	onClose: () => void;
	onSaved: (client: ClientResponse) => void;
}) {
	const i18n = useI18n();
	const { t } = i18n;
	const schema = useMemo(() => makeSchema(t), [t]);
	const me = useMe();
	const editing = target.mode === "edit" ? target.client : null;
	const create = useCreateClient(onSaved);
	const update = useUpdateClient(editing?.id ?? 0, onSaved);
	const mutation = editing ? update : create;
	const salesUsers = useSalesUsers(can.assignClients(me.role));

	const form = useAppForm({
		defaultValues: {
			name: editing?.name ?? "",
			nip: editing?.nip ?? "",
			email: editing?.email ?? "",
			phone: editing?.phone ?? "",
			city: editing?.city ?? "",
			status: (editing?.status ?? "LEAD") as Values["status"],
			assignedUserId: editing?.assignedUserId ? String(editing.assignedUserId) : "",
			note: editing?.note ?? "",
		} satisfies Values,
		validators: { onChange: schema },
		onSubmit: ({ value }) =>
			mutation.mutate({
				name: value.name.trim(),
				nip: orNull(value.nip.replace(/[\s-]/g, "")),
				email: orNull(value.email),
				phone: orNull(value.phone),
				city: orNull(value.city),
				status: value.status,
				// SALES: the procedure assigns the client to the actor.
				assignedUserId: value.assignedUserId
					? Number(value.assignedUserId)
					: (editing?.assignedUserId ?? null),
				note: orNull(value.note),
				rowVersion: editing?.rowVersion ?? null,
			}),
	});

	return (
		<FormDrawer
			title={editing ? t("Edycja klienta", "Edit client") : t("Nowy klient", "New client")}
			description={
				editing
					? editing.name
					: t(
							"Potencjalny, aktywny albo do archiwum.",
							"A lead, an active client or one to archive.",
						)
			}
			onClose={onClose}
			onSubmit={() => void form.handleSubmit()}
		>
			<FormDrawer.Body>
				<form.AppField name="name">
					{(f) => (
						<f.FormInput
							label={t("Nazwa firmy", "Company name")}
							placeholder="Zielony Most Sp. z o.o."
							autoFocus
						/>
					)}
				</form.AppField>
				<div className="grid grid-cols-2 gap-4">
					<form.AppField name="nip">
						{(f) => <f.FormInput label="NIP" placeholder="1234567890" inputMode="numeric" />}
					</form.AppField>
					<form.AppField name="status">
						{(f) => (
							<f.FormSelect
								label={t("Status", "Status")}
								options={CLIENT_STATUSES.map((s) => ({ id: s, label: clientStatusLabel(s, i18n) }))}
							/>
						)}
					</form.AppField>
				</div>
				<form.AppField name="email">
					{(f) => (
						<f.FormInput
							label="E-mail"
							type="email"
							placeholder={t("biuro@example.com", "office@example.com")}
						/>
					)}
				</form.AppField>
				<div className="grid grid-cols-2 gap-4">
					<form.AppField name="phone">
						{(f) => (
							<f.FormInput label={t("Telefon", "Phone")} type="tel" placeholder="+48 500 000 000" />
						)}
					</form.AppField>
					<form.AppField name="city">
						{(f) => (
							<f.FormSelect
								label={t("Miasto", "City")}
								options={CITIES.map((c) => ({ id: c, label: c }))}
							/>
						)}
					</form.AppField>
				</div>
				{can.assignClients(me.role) ? (
					<form.AppField name="assignedUserId">
						{(f) => (
							<f.FormSelect
								label={t("Opiekun klienta", "Account owner")}
								placeholder={
									salesUsers.isPending
										? t("Wczytywanie sprzedawców…", "Loading sales users…")
										: t("Nieprzypisany", "Unassigned")
								}
								options={(salesUsers.data ?? []).map((u) => ({
									id: String(u.id),
									label: u.displayName,
									description: u.login,
								}))}
								description={t(
									"Opiekunem klienta jest jeden aktywny sprzedawca.",
									"A client is owned by one active sales user.",
								)}
							/>
						)}
					</form.AppField>
				) : null}
				<form.AppField name="note">
					{(f) => (
						<f.FormTextArea
							label={t("Notatka", "Note")}
							placeholder={t("Wszystko, co warto zapamiętać", "Anything worth remembering")}
							rows={3}
						/>
					)}
				</form.AppField>
				<ApiError error={mutation.error} />
			</FormDrawer.Body>
			<FormDrawer.Footer
				submitLabel={
					editing ? t("Zapisz zmiany", "Save changes") : t("Dodaj klienta", "Create client")
				}
				isPending={mutation.isPending}
			/>
		</FormDrawer>
	);
}
