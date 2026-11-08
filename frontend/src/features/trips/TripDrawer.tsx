import {
	Checkbox,
	Input,
	Label,
	ListBox,
	SearchField,
	Select,
	TextArea,
	TextField,
	toast,
} from "@heroui/react";
import { useInfiniteQuery, useQuery } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import { forwardRef, type ReactNode, useImperativeHandle, useState } from "react";
import type { TripResponse } from "#/api/models";
import { ApiError, DateTimeInput, FormDrawer } from "#/components/ui";
import { useMe } from "#/features/auth/session";
import { ClientPicker } from "#/features/clients/ClientPicker";
import { CompanySelect } from "#/features/companies/CompanySelect";
import { carsQuery } from "#/features/fleet/hooks";
import { projectsQuery } from "#/features/projects/hooks";
import { PersonPicker } from "#/features/users/PersonPicker";
import { useDebouncedValue } from "#/hooks/useDebouncedValue";
import { useI18n } from "#/i18n";
import { tripRatesQuery, useCreateTrip, useUpdateTrip } from "./hooks";
import {
	PURPOSE_ICONS,
	PURPOSES,
	type Purpose,
	purposeLabel,
	TRANSPORTS,
	transportLabel,
} from "./types";

export interface TripDrawerCommand {
	create: () => void;
	edit: (trip: TripResponse) => void;
}

/** Plan or correct a trip (ADR-0019): what for, where, when, how; meals, nights and the advance for the settlement. */
export const TripDrawer = forwardRef<TripDrawerCommand>((_, ref) => {
	const [target, setTarget] = useState<{ trip?: TripResponse } | null>(null);
	useImperativeHandle(
		ref,
		() => ({ create: () => setTarget({}), edit: (trip) => setTarget({ trip }) }),
		[],
	);
	if (!target) return null;
	return (
		<Content key={target.trip?.id ?? "new"} trip={target.trip} onClose={() => setTarget(null)} />
	);
});

const inHours = (hours: number) => {
	const d = new Date();
	d.setMinutes(0, 0, 0);
	d.setHours(d.getHours() + hours);
	return d.toISOString();
};

function Content({ trip, onClose }: { trip?: TripResponse; onClose: () => void }) {
	const i18n = useI18n();
	const { t, lang } = i18n;
	const me = useMe();
	const manager = me.role === "ADMIN" || me.role === "MANAGER";
	const goTo = useNavigate();
	const rates = useQuery(tripRatesQuery());
	const [traveller, setTraveller] = useState<{ id: number; name: string }>();
	const [purpose, setPurpose] = useState<Purpose>((trip?.purpose as Purpose) ?? "CLIENT_VISIT");
	const [client, setClient] = useState(
		trip?.clientId ? { id: trip.clientId, name: trip.clientName ?? "" } : undefined,
	);
	const [projectId, setProjectId] = useState<number | undefined>(trip?.projectId ?? undefined);
	const [eventName, setEventName] = useState(trip?.eventName ?? "");
	const [description, setDescription] = useState(trip?.description ?? "");
	const [destination, setDestination] = useState(trip?.destination ?? "");
	const [country, setCountry] = useState(trip?.country ?? "PL");
	const [startsAt, setStartsAt] = useState(trip?.startsAt ?? inHours(24));
	const [endsAt, setEndsAt] = useState(trip?.endsAt ?? inHours(34));
	const [transport, setTransport] = useState(trip?.transport ?? "COMPANY_CAR");
	const [car, setCar] = useState(
		trip?.carId ? { id: trip.carId, name: trip.carPlate ?? "" } : undefined,
	);
	const [vehicle, setVehicle] = useState(trip?.vehicle ?? "CAR_GT_900");
	const [km, setKm] = useState(trip?.kilometres ? String(trip.kilometres) : "");
	const [breakfasts, setBreakfasts] = useState(String(trip?.breakfasts ?? 0));
	const [lunches, setLunches] = useState(String(trip?.lunches ?? 0));
	const [dinners, setDinners] = useState(String(trip?.dinners ?? 0));
	const [lumpNights, setLumpNights] = useState(String(trip?.lumpNights ?? 0));
	const [localTransport, setLocalTransport] = useState(trip?.localTransport ?? false);
	const [advance, setAdvance] = useState(trip ? String(trip.advance) : "0");
	const [company, setCompany] = useState<number | undefined>(trip?.legalEntityId);

	const projects = useInfiniteQuery({
		...projectsQuery({ clientId: client?.id }),
		enabled: purpose === "PROJECT_SITE" && client != null,
	});
	const created = useCreateTrip((tr) => {
		toast.success(t(`Zaplanowano ${tr.number}`, `Planned ${tr.number}`));
		onClose();
		void goTo({ to: "/trips/$tripId", params: { tripId: tr.id } });
	});
	const updated = useUpdateTrip(trip?.id ?? 0, () => {
		toast.success(t("Zapisano delegację", "Trip saved"));
		onClose();
	});
	const mutation = trip ? updated : created;
	const num = (v: string) => (v.trim() === "" ? 0 : Number(v.replace(",", ".")));

	const submit = () =>
		mutation.mutate({
			travellerUserId: trip ? null : (traveller?.id ?? null),
			purpose,
			clientId: purpose === "CLIENT_VISIT" ? (client?.id ?? null) : null,
			projectId: purpose === "PROJECT_SITE" ? (projectId ?? null) : null,
			eventName: purpose === "TRADE_FAIR" ? eventName : null,
			description,
			destination,
			country,
			startsAt,
			endsAt,
			transport,
			carId: transport === "COMPANY_CAR" ? (car?.id ?? null) : null,
			vehicle: transport === "PRIVATE_CAR" ? vehicle : null,
			kilometres: transport === "PRIVATE_CAR" ? num(km) : null,
			breakfasts: num(breakfasts),
			lunches: num(lunches),
			dinners: num(dinners),
			lumpNights: num(lumpNights),
			localTransport,
			advance: num(advance),
			legalEntityId: company ?? null,
			rowVersion: trip?.rowVersion ?? null,
		});

	const countries = (rates.data ?? []).filter((r) => r.kind === "COUNTRY");
	const vehicles = (rates.data ?? []).filter((r) => r.kind === "VEHICLE");
	return (
		<FormDrawer
			title={trip ? trip.number : t("Nowa delegacja", "New trip")}
			description={t(
				"Rozliczenie liczy się samo: diety, ryczałty i kilometrówka według stawek z przepisów.",
				"The settlement computes itself: per diems, lump sums and mileage at the regulation's rates.",
			)}
			onClose={onClose}
			onSubmit={submit}
		>
			<FormDrawer.Body>
				{!trip && manager ? (
					<PersonPicker
						label={t("Kto jedzie (puste - ja)", "Who travels (empty - me)")}
						value={traveller}
						onChange={setTraveller}
					/>
				) : null}
				<fieldset className="grid grid-cols-2 gap-1.5">
					<legend className="mb-1.5 text-sm font-medium">{t("Cel wyjazdu", "Purpose")}</legend>
					{PURPOSES.map((p) => {
						const Icon = PURPOSE_ICONS[p];
						return (
							<button
								key={p}
								type="button"
								aria-pressed={purpose === p}
								onClick={() => setPurpose(p)}
								className={`flex items-center gap-2 rounded-md border px-3 py-2 text-left text-xs transition-colors ${purpose === p ? "border-[var(--obs-ink)] bg-[var(--obs-ink)] text-white" : "border-separator hover:bg-[var(--obs-surface-hover)]"}`}
							>
								<Icon className="size-4" />
								{purposeLabel(p, i18n)}
							</button>
						);
					})}
				</fieldset>
				{purpose === "CLIENT_VISIT" || purpose === "PROJECT_SITE" ? (
					<ClientPicker required value={client} onChange={setClient} />
				) : null}
				{purpose === "PROJECT_SITE" && client ? (
					<Pick
						label={t("Projekt", "Project")}
						value={projectId ? String(projectId) : undefined}
						onChange={(v) => setProjectId(Number(v))}
						options={(projects.data?.pages[0]?.items ?? []).map((p) => ({
							id: String(p.id),
							label: p.name,
						}))}
					/>
				) : null}
				{purpose === "TRADE_FAIR" ? (
					<Text
						label={t("Targi / wydarzenie", "Trade fair / event")}
						value={eventName}
						onChange={setEventName}
						max={200}
					/>
				) : null}
				<div className="grid grid-cols-[1fr_11rem] gap-3">
					<Text
						label={t("Dokąd (miasto)", "Destination (city)")}
						value={destination}
						onChange={setDestination}
						max={120}
					/>
					<Pick
						label={t("Kraj", "Country")}
						value={country}
						onChange={setCountry}
						options={countries.map((c) => ({
							id: c.code,
							label: lang === "pl" ? c.namePl : c.nameEn,
						}))}
					/>
				</div>
				<div className="grid grid-cols-2 gap-3">
					<DateTimeInput label={t("Wyjazd", "Departure")} value={startsAt} onChange={setStartsAt} />
					<DateTimeInput label={t("Powrót", "Return")} value={endsAt} onChange={setEndsAt} />
				</div>
				<Pick
					label={t("Transport", "Transport")}
					value={transport}
					onChange={setTransport}
					options={TRANSPORTS.map((x) => ({ id: x, label: transportLabel(x, i18n) }))}
				/>
				{transport === "COMPANY_CAR" ? <CarPicker value={car} onChange={setCar} /> : null}
				{transport === "PRIVATE_CAR" ? (
					<div className="grid grid-cols-[1fr_7rem] gap-3">
						<Pick
							label={t("Pojazd", "Vehicle")}
							value={vehicle}
							onChange={setVehicle}
							options={vehicles.map((v) => ({
								id: v.code,
								label: `${lang === "pl" ? v.namePl : v.nameEn} · ${Number(v.amount).toFixed(2)} zł/km`,
							}))}
						/>
						<Text label="km" value={km} onChange={setKm} numeric />
					</div>
				) : null}
				<Section
					title={t(
						"Zapewnione posiłki (pomniejszają diety)",
						"Meals provided (reduce the per diems)",
					)}
				>
					<div className="grid grid-cols-3 gap-3">
						<Text
							label={t("Śniadania", "Breakfasts")}
							value={breakfasts}
							onChange={setBreakfasts}
							numeric
						/>
						<Text label={t("Obiady", "Lunches")} value={lunches} onChange={setLunches} numeric />
						<Text label={t("Kolacje", "Dinners")} value={dinners} onChange={setDinners} numeric />
					</div>
				</Section>
				<Section
					title={t(
						"Noclegi i dojazdy bez rachunków (ryczałty)",
						"Nights and local transport without receipts (lump sums)",
					)}
				>
					<div className="grid grid-cols-2 items-end gap-3">
						<Text
							label={t("Noclegi bez faktury", "Nights without invoice")}
							value={lumpNights}
							onChange={setLumpNights}
							numeric
						/>
						<Checkbox isSelected={localTransport} onChange={setLocalTransport} className="pb-2">
							<Checkbox.Content>
								<Checkbox.Control>
									<Checkbox.Indicator />
								</Checkbox.Control>
								<Label>{t("Ryczałt za dojazdy", "Local transport lump sum")}</Label>
							</Checkbox.Content>
						</Checkbox>
					</div>
				</Section>
				<div className="grid grid-cols-2 items-end gap-3">
					<Text label={t("Zaliczka", "Advance")} value={advance} onChange={setAdvance} numeric />
					<CompanySelect
						label={t("Spółka płacąca", "Paying company")}
						value={company}
						onChange={setCompany}
					/>
				</div>
				<TextField value={description} onChange={setDescription} fullWidth>
					<Label>{t("Opis", "Description")}</Label>
					<TextArea rows={2} maxLength={1000} />
				</TextField>
				<ApiError error={mutation.error} />
			</FormDrawer.Body>
			<FormDrawer.Footer
				isPending={mutation.isPending}
				submitLabel={trip ? undefined : t("Zaplanuj", "Plan")}
			/>
		</FormDrawer>
	);
}

function Section({ title, children }: { title: string; children: ReactNode }) {
	return (
		<section className="flex flex-col gap-2 rounded-lg border border-separator bg-[var(--obs-surface-subtle)] p-3">
			<p className="text-xs font-medium text-[var(--obs-text-secondary)]">{title}</p>
			{children}
		</section>
	);
}

function Text({
	label,
	value,
	onChange,
	max,
	numeric,
}: {
	label: string;
	value: string;
	onChange: (v: string) => void;
	max?: number;
	numeric?: boolean;
}) {
	return (
		<TextField
			value={value}
			onChange={(v) => onChange(numeric ? v.replace(/[^\d.,]/g, "") : v)}
			fullWidth
		>
			<Label>{label}</Label>
			<Input maxLength={max} inputMode={numeric ? "decimal" : undefined} />
		</TextField>
	);
}

function Pick({
	label,
	value,
	onChange,
	options,
}: {
	label: string;
	value: string | undefined;
	onChange: (v: string) => void;
	options: { id: string; label: string }[];
}) {
	const { t } = useI18n();
	return (
		<Select
			value={value ?? null}
			onChange={(k) => k != null && onChange(String(k))}
			placeholder={t("Wybierz…", "Select…")}
			fullWidth
		>
			<Label>{label}</Label>
			<Select.Trigger>
				<Select.Value />
				<Select.Indicator />
			</Select.Trigger>
			<Select.Popover>
				<ListBox>
					{options.map((o) => (
						<ListBox.Item key={o.id} id={o.id} textValue={o.label}>
							{o.label}
							<ListBox.ItemIndicator />
						</ListBox.Item>
					))}
				</ListBox>
			</Select.Popover>
		</Select>
	);
}

/** A free car of the fleet by plate or name (optional: the trip can go without naming it). */
function CarPicker({
	value,
	onChange,
}: {
	value: { id: number; name: string } | undefined;
	onChange: (v: { id: number; name: string } | undefined) => void;
}) {
	const { t } = useI18n();
	const [text, setText] = useState("");
	const search = useDebouncedValue(text.trim(), 300);
	const cars = useInfiniteQuery({
		...carsQuery({ search: search || undefined }, 6),
		enabled: search.length > 0,
	});
	const items = cars.data?.pages[0]?.items ?? [];
	return (
		<section className="flex flex-col gap-2">
			<p className="text-sm font-medium">
				{t("Samochód z floty", "Fleet car")}
				{value ? <span className="ml-2 font-mono text-xs text-muted">{value.name}</span> : null}
			</p>
			<SearchField
				aria-label={t("Szukaj samochodu", "Search cars")}
				value={text}
				onChange={setText}
				fullWidth
			>
				<SearchField.Group>
					<SearchField.SearchIcon />
					<SearchField.Input placeholder={t("Rejestracja albo model…", "Plate or model…")} />
					<SearchField.ClearButton />
				</SearchField.Group>
			</SearchField>
			{search && items.length > 0 ? (
				<ListBox
					aria-label={t("Samochody", "Cars")}
					selectionMode="single"
					className="max-h-44 overflow-y-auto rounded-md border border-separator"
					onSelectionChange={(keys) => {
						const key = keys === "all" ? undefined : [...keys][0];
						const found = items.find((c) => c.id === Number(key));
						if (found) {
							onChange({ id: found.id, name: `${found.plate} · ${found.name}` });
							setText("");
						}
					}}
				>
					{items.map((c) => (
						<ListBox.Item key={c.id} id={c.id} textValue={c.plate}>
							<span className="flex w-full justify-between gap-3">
								<span>{c.name}</span>
								<span className="font-mono text-xs text-muted">{c.plate}</span>
							</span>
						</ListBox.Item>
					))}
				</ListBox>
			) : null}
		</section>
	);
}
