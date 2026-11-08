import { toast } from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { forwardRef, useImperativeHandle, useMemo, useState } from "react";
import { z } from "zod";
import type { UserContactResponse } from "#/api/models";
import { ApiError, FormDrawer } from "#/components/ui";
import { useAppForm } from "#/forms";
import { useI18n } from "#/i18n";
import {
	myContactQuery,
	userContactQuery,
	useUpdateMyContact,
	useUpdateUserContact,
} from "./hooks";

export interface ContactCommand {
	/** Edit my own contact, or a user's (administrators). */
	open: (userId?: number) => void;
}

/**
 * The contact that closes a salesperson's offers (ADR-0013): job title, phone, e-mail. Everybody edits their own,
 * administrators anyone's; the procedure checks the values.
 */
export const ContactDrawer = forwardRef<ContactCommand>((_, ref) => {
	const [target, setTarget] = useState<{ userId?: number } | null>(null);
	useImperativeHandle(ref, () => ({ open: (userId) => setTarget({ userId }) }), []);
	if (!target) return null;
	return <Loader userId={target.userId} onClose={() => setTarget(null)} />;
});

function Loader({ userId, onClose }: { userId?: number; onClose: () => void }) {
	const mine = useQuery({ ...myContactQuery(), enabled: userId == null });
	const theirs = useQuery({ ...userContactQuery(userId ?? 0), enabled: userId != null });
	const contact = userId == null ? mine.data : theirs.data;
	if (!contact) return null;
	return <Content contact={contact} userId={userId} onClose={onClose} />;
}

function Content({
	contact,
	userId,
	onClose,
}: {
	contact: UserContactResponse;
	userId?: number;
	onClose: () => void;
}) {
	const { t } = useI18n();
	const schema = useMemo(
		() =>
			z.object({
				jobTitle: z.string().max(100, t("Najwyżej 100 znaków", "At most 100 characters")),
				phone: z
					.string()
					.trim()
					.refine(
						(v) => v === "" || /^[0-9 +()-]{6,30}$/.test(v),
						t("6-30 cyfr, spacji i + ( ) -", "6-30 digits, spaces and + ( ) -"),
					),
				email: z
					.string()
					.trim()
					.refine(
						(v) => v === "" || z.email().safeParse(v).success,
						t("To nie jest adres e-mail", "Not a valid e-mail"),
					),
			}),
		[t],
	);
	const done = () => {
		toast.success(t("Zapisano kontakt", "Contact saved"));
		onClose();
	};
	const mine = useUpdateMyContact(done);
	const theirs = useUpdateUserContact(userId ?? 0, done);
	const mutation = userId == null ? mine : theirs;
	const form = useAppForm({
		defaultValues: {
			jobTitle: contact.jobTitle ?? "",
			phone: contact.phone ?? "",
			email: contact.email ?? "",
		},
		validators: { onChange: schema },
		onSubmit: ({ value }) => mutation.mutate(value),
	});
	return (
		<FormDrawer
			title={userId == null ? t("Mój kontakt", "My contact") : contact.displayName}
			description={t(
				"Zamyka oferty, które przygotujesz jako sprzedawca: stanowisko, telefon i e-mail.",
				"It closes the offers you prepare as a salesperson: job title, phone and e-mail.",
			)}
			onClose={onClose}
			onSubmit={() => void form.handleSubmit()}
		>
			<FormDrawer.Body>
				<form.AppField name="jobTitle">
					{(f) => (
						<f.FormInput
							label={t("Stanowisko", "Job title")}
							placeholder={t("Doradca handlowy", "Sales advisor")}
						/>
					)}
				</form.AppField>
				<form.AppField name="phone">
					{(f) => (
						<f.FormInput label={t("Telefon", "Phone")} type="tel" placeholder="+48 600 100 200" />
					)}
				</form.AppField>
				<form.AppField name="email">
					{(f) => <f.FormInput label="E-mail" type="email" />}
				</form.AppField>
				<ApiError error={mutation.error} />
			</FormDrawer.Body>
			<FormDrawer.Footer isPending={mutation.isPending} />
		</FormDrawer>
	);
}
