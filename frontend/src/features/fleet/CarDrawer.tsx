import { toast } from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { forwardRef, useImperativeHandle, useMemo, useState } from "react";
import { z } from "zod";
import type { CarResponse } from "#/api/models";
import { ApiError, FormDrawer } from "#/components/ui";
import { useMe } from "#/features/auth/session";
import { legalEntitiesQuery, pickable } from "#/features/companies/hooks";
import { useAppForm } from "#/forms";
import { useI18n } from "#/i18n";
import { carMakesQuery, useCreateCar, useUpdateCar } from "./hooks";

export interface CarDrawerCommand {
	create: () => void;
	edit: (car: CarResponse) => void;
}

/** A car's data (ADR-0018): name, make, year, plate, VIN, company, inspection and insurance deadlines, notes. */
export const CarDrawer = forwardRef<CarDrawerCommand>((_, ref) => {
	const [target, setTarget] = useState<{ car?: CarResponse } | null>(null);
	useImperativeHandle(
		ref,
		() => ({ create: () => setTarget({}), edit: (car) => setTarget({ car }) }),
		[],
	);
	if (!target) return null;
	return <Content key={target.car?.id ?? "new"} car={target.car} onClose={() => setTarget(null)} />;
});

function Content({ car, onClose }: { car?: CarResponse; onClose: () => void }) {
	const { t } = useI18n();
	const me = useMe();
	const entities = useQuery(legalEntitiesQuery());
	const makes = useQuery(carMakesQuery());
	const nextYear = new Date().getFullYear() + 1;
	const schema = useMemo(
		() =>
			z.object({
				name: z.string().trim().min(1, t("Nazwa jest wymagana", "The name is required")).max(100),
				make: z.string().max(60),
				productionYear: z
					.string()
					.refine(
						(v) => v === "" || (/^\d{4}$/.test(v) && Number(v) >= 1900 && Number(v) <= nextYear),
						t(`Rok 1900-${nextYear}`, `Year 1900-${nextYear}`),
					),
				plate: z
					.string()
					.trim()
					.regex(
						/^[A-Za-z0-9][A-Za-z0-9 -]{0,14}$/,
						t(
							"Litery, cyfry, spacje i myślniki, do 15",
							"Letters, digits, spaces and hyphens, up to 15",
						),
					),
				vin: z
					.string()
					.trim()
					.refine(
						(v) => v === "" || /^[A-HJ-NPR-Za-hj-npr-z0-9]{17}$/.test(v),
						t("17 znaków bez I, O, Q", "17 characters without I, O, Q"),
					),
				vinReason: z.string().max(400),
				legalEntityId: z.string().min(1, t("Wybierz spółkę", "Choose a company")),
				inspectionDue: z.string(),
				insuranceDue: z.string(),
				notes: z.string().max(1000),
			}),
		[t, nextYear],
	);
	const done = () => {
		toast.success(t("Zapisano samochód", "Car saved"));
		onClose();
	};
	const create = useCreateCar(done);
	const update = useUpdateCar(car?.id ?? 0, done);
	const mutation = car ? update : create;
	const form = useAppForm({
		defaultValues: {
			name: car?.name ?? "",
			make: car?.make ?? "",
			productionYear: car?.productionYear ? String(car.productionYear) : "",
			plate: car?.plate ?? "",
			vin: car?.vin ?? "",
			vinReason: "",
			legalEntityId: car ? String(car.legalEntityId) : "",
			inspectionDue: car?.inspectionDue ?? "",
			insuranceDue: car?.insuranceDue ?? "",
			notes: car?.notes ?? "",
		},
		validators: { onChange: schema },
		onSubmit: ({ value }) =>
			mutation.mutate({
				name: value.name.trim(),
				make: value.make || null,
				productionYear: value.productionYear ? Number(value.productionYear) : null,
				plate: value.plate.trim(),
				vin: value.vin.trim() || null,
				vinReason: value.vinReason || null,
				legalEntityId: Number(value.legalEntityId),
				inspectionDue: value.inspectionDue || null,
				insuranceDue: value.insuranceDue || null,
				notes: value.notes || null,
				rowVersion: car?.rowVersion ?? null,
			}),
	});
	// A VIN once given is corrected only by an administrator, with a reason (app.car_save).
	const vinLocked = Boolean(car?.vin) && me.role !== "ADMIN";
	return (
		<FormDrawer
			title={car ? car.name : t("Nowy samochód", "New car")}
			description={
				car
					? car.plate
					: t(
							"Status „Nowy” od dziś; przekazać można od razu.",
							"Status “New” from today; it can be handed over at once.",
						)
			}
			onClose={onClose}
			onSubmit={() => void form.handleSubmit()}
		>
			<FormDrawer.Body>
				<form.AppField name="name">
					{(f) => (
						<f.FormInput
							label={t("Nazwa", "Name")}
							placeholder="Škoda Octavia Kombi"
							autoFocus={!car}
						/>
					)}
				</form.AppField>
				<div className="grid grid-cols-[1fr_7rem] gap-3">
					<form.AppField name="make">
						{(f) => (
							<f.FormSelect
								label={t("Marka", "Make")}
								options={[
									{ id: "", label: "—" },
									...(makes.data ?? []).map((m) => ({ id: m, label: m })),
								]}
							/>
						)}
					</form.AppField>
					<form.AppField name="productionYear">
						{(f) => <f.FormInput label={t("Rok", "Year")} inputMode="numeric" />}
					</form.AppField>
				</div>
				<div className="grid grid-cols-2 gap-3">
					<form.AppField name="plate">
						{(f) => <f.FormInput label={t("Rejestracja", "Plate")} placeholder="WA 12345" />}
					</form.AppField>
					<form.AppField name="legalEntityId">
						{(f) => (
							<f.FormSelect
								label={t("Spółka", "Company")}
								options={pickable(entities.data, car?.legalEntityId).map((e) => ({
									id: String(e.id),
									label: e.name,
								}))}
							/>
						)}
					</form.AppField>
				</div>
				<form.AppField name="vin">
					{(f) => (
						<f.FormInput
							label="VIN"
							description={
								vinLocked
									? t("Poprawia administrator.", "An administrator corrects it.")
									: undefined
							}
						/>
					)}
				</form.AppField>
				{car?.vin && !vinLocked ? (
					<form.AppField name="vinReason">
						{(f) => (
							<f.FormInput
								label={t("Powód korekty VIN (jeśli zmieniasz)", "Why the VIN changes (if it does)")}
							/>
						)}
					</form.AppField>
				) : null}
				<div className="grid grid-cols-2 gap-3">
					<form.AppField name="inspectionDue">
						{(f) => <f.FormDate label={t("Przegląd do", "Inspection until")} />}
					</form.AppField>
					<form.AppField name="insuranceDue">
						{(f) => <f.FormDate label={t("OC do", "Insurance until")} />}
					</form.AppField>
				</div>
				<form.AppField name="notes">
					{(f) => <f.FormTextArea label={t("Notatki", "Notes")} rows={3} />}
				</form.AppField>
				<ApiError error={mutation.error} />
			</FormDrawer.Body>
			<FormDrawer.Footer isPending={mutation.isPending} />
		</FormDrawer>
	);
}
