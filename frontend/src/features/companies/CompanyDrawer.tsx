import { toast } from "@heroui/react";
import { forwardRef, useImperativeHandle, useMemo, useState } from "react";
import { z } from "zod";
import type { LegalEntityResponse } from "#/api/models";
import { ApiError, FormDrawer } from "#/components/ui";
import { useAppForm } from "#/forms";
import { useI18n } from "#/i18n";
import { todayIso } from "#/lib";
import { useCreateLegalEntity, useUpdateLegalEntity } from "./hooks";

export interface CompanyCommand {
	create: () => void;
	edit: (entity: LegalEntityResponse) => void;
}

/** The NIP check digit: weights 6 5 7 2 3 4 5 6 7, sum mod 11 (mirrors crm.legal_entity_check, which decides). */
const validNip = (value: string) => {
	const d = value.replace(/[\s-]/g, "");
	if (!/^\d{10}$/.test(d)) return false;
	const w = [6, 5, 7, 2, 3, 4, 5, 6, 7];
	return w.reduce((sum, x, i) => sum + x * Number(d[i]), 0) % 11 === Number(d[9]);
};

/** Add or change a company (ADMIN). Closing is the last trading day: the company stays for its projects and offers. */
export const CompanyDrawer = forwardRef<CompanyCommand>((_, ref) => {
	const [target, setTarget] = useState<{ entity?: LegalEntityResponse } | null>(null);
	useImperativeHandle(
		ref,
		() => ({ create: () => setTarget({}), edit: (entity) => setTarget({ entity }) }),
		[],
	);
	if (!target) return null;
	return (
		<Content
			key={target.entity?.id ?? "new"}
			entity={target.entity}
			onClose={() => setTarget(null)}
		/>
	);
});

function Content({ entity, onClose }: { entity?: LegalEntityResponse; onClose: () => void }) {
	const { t } = useI18n();
	const schema = useMemo(
		() =>
			z
				.object({
					name: z.string().trim().min(1, t("Nazwa jest wymagana", "The name is required")).max(100),
					legalName: z
						.string()
						.trim()
						.min(1, t("Pełna nazwa jest wymagana", "The legal name is required"))
						.max(200),
					taxId: z
						.string()
						.refine(
							validNip,
							t("10 cyfr z poprawną cyfrą kontrolną", "10 digits with a valid check digit"),
						),
					vatNumber: z.string().max(20),
					address: z
						.string()
						.trim()
						.min(1, t("Adres jest wymagany", "The address is required"))
						.max(300),
					phone: z.string().max(30),
					email: z
						.string()
						.trim()
						.refine(
							(v) => v === "" || z.email().safeParse(v).success,
							t("To nie jest adres e-mail", "Not a valid e-mail"),
						),
					website: z.string().max(200),
					bankAccount: z.string().max(40),
					activeFrom: z.iso.date(t("Podaj datę", "Enter a date")),
					activeTo: z.string(),
				})
				.refine((v) => v.activeTo === "" || v.activeTo >= v.activeFrom, {
					path: ["activeTo"],
					message: t("Koniec nie może być przed początkiem", "The end cannot be before the start"),
				}),
		[t],
	);
	const done = () => {
		toast.success(t("Zapisano spółkę", "Company saved"));
		onClose();
	};
	const create = useCreateLegalEntity(done);
	const update = useUpdateLegalEntity(entity?.id ?? 0, done);
	const mutation = entity ? update : create;
	const form = useAppForm({
		defaultValues: {
			name: entity?.name ?? "",
			legalName: entity?.legalName ?? "",
			taxId: entity?.taxId ?? "",
			vatNumber: entity?.vatNumber ?? "",
			address: entity?.address ?? "",
			phone: entity?.phone ?? "",
			email: entity?.email ?? "",
			website: entity?.website ?? "",
			bankAccount: entity?.bankAccount ?? "",
			activeFrom: entity?.activeFrom ?? todayIso(),
			activeTo: entity?.activeTo ?? "",
		},
		validators: { onChange: schema },
		onSubmit: ({ value }) =>
			mutation.mutate({
				...value,
				vatNumber: value.vatNumber || null,
				phone: value.phone || null,
				email: value.email || null,
				website: value.website || null,
				bankAccount: value.bankAccount || null,
				activeTo: value.activeTo || null,
				rowVersion: entity?.rowVersion ?? null,
			}),
	});
	return (
		<FormDrawer
			title={entity ? entity.name : t("Nowa spółka", "New company")}
			description={t(
				"Dane na ofertach i projektach. Spółkę zamyka się datą ostatniego dnia działalności.",
				"What offers and projects show. A company is closed with its last trading day.",
			)}
			onClose={onClose}
			onSubmit={() => void form.handleSubmit()}
		>
			<FormDrawer.Body>
				<form.AppField name="name">
					{(f) => (
						<f.FormInput label={t("Nazwa", "Name")} placeholder="Halycon IT" autoFocus={!entity} />
					)}
				</form.AppField>
				<form.AppField name="legalName">
					{(f) => (
						<f.FormInput
							label={t("Pełna nazwa", "Legal name")}
							placeholder="Halycon IT sp. z o.o."
						/>
					)}
				</form.AppField>
				<div className="grid grid-cols-2 gap-3">
					<form.AppField name="taxId">
						{(f) => <f.FormInput label="NIP" inputMode="numeric" />}
					</form.AppField>
					<form.AppField name="vatNumber">
						{(f) => <f.FormInput label={t("NIP UE (VAT)", "EU VAT number")} placeholder="PL…" />}
					</form.AppField>
				</div>
				<form.AppField name="address">
					{(f) => <f.FormInput label={t("Adres", "Address")} />}
				</form.AppField>
				<div className="grid grid-cols-2 gap-3">
					<form.AppField name="phone">
						{(f) => <f.FormInput label={t("Telefon", "Phone")} type="tel" />}
					</form.AppField>
					<form.AppField name="email">
						{(f) => <f.FormInput label="E-mail" type="email" />}
					</form.AppField>
				</div>
				<form.AppField name="website">{(f) => <f.FormInput label="WWW" />}</form.AppField>
				<form.AppField name="bankAccount">
					{(f) => <f.FormInput label={t("Rachunek bankowy (IBAN)", "Bank account (IBAN)")} />}
				</form.AppField>
				<div className="grid grid-cols-2 gap-3">
					<form.AppField name="activeFrom">
						{(f) => <f.FormDate label={t("Działa od", "Trades from")} />}
					</form.AppField>
					<form.AppField name="activeTo">
						{(f) => (
							<f.FormDate
								label={t("Działa do", "Trades until")}
								description={t("Puste, dopóki działa", "Empty while it trades")}
							/>
						)}
					</form.AppField>
				</div>
				<ApiError error={mutation.error} />
			</FormDrawer.Body>
			<FormDrawer.Footer isPending={mutation.isPending} />
		</FormDrawer>
	);
}
