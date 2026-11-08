import {
	Button,
	Card,
	Chip,
	Input,
	Label,
	ListBox,
	Select,
	Skeleton,
	TextArea,
	TextField,
	toast,
} from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { getRouteApi, Link, useNavigate } from "@tanstack/react-router";
import { ArrowLeft, FileDown, FileText, Pencil, Plus, Trash2, X } from "lucide-react";
import { useState } from "react";
import type { OfferItemResponse, OfferResponse } from "#/api/models";
import { PageHeader } from "#/components/layout/AppLayout";
import { ApiError, ConfirmDialog, DateInput, InfoList } from "#/components/ui";
import { CompanySelect } from "#/features/companies/CompanySelect";
import { useI18n } from "#/i18n";
import { problemText } from "#/i18n/problems";
import {
	offerItemsQuery,
	offerPdfUrl,
	offerQuery,
	useChangeOfferStatus,
	useDeleteOffer,
	useUpdateOffer,
} from "./hooks";
import {
	CURRENCIES,
	money,
	NEXT_OFFER_STATUSES,
	type OfferStatus,
	offerAction,
	offerStatusColor,
	offerStatusLabel,
	templateName,
	VAT_RATES,
} from "./types";

const route = getRouteApi("/_app/offers/$offerId");

/** An offer: its lines and totals, the status moves, the PDF; a draft is edited in place. */
export function OfferDetailsPage() {
	const { offerId } = route.useParams();
	const i18n = useI18n();
	const { t, locale, lang } = i18n;
	const navigate = useNavigate();
	const offer = useQuery(offerQuery(offerId));
	const items = useQuery(offerItemsQuery(offerId));
	const [editing, setEditing] = useState(false);
	const [confirmDelete, setConfirmDelete] = useState(false);
	const status = useChangeOfferStatus(offerId, (o) =>
		toast.success(offerStatusLabel(o.status, i18n)),
	);
	const remove = useDeleteOffer(() => {
		toast.success(t("Usunięto szkic oferty", "Draft offer deleted"));
		void navigate({ to: "/offers", search: {} });
	});

	const back = (
		<Link to="/offers" search={{}} className="inline-flex items-center gap-1 hover:text-foreground">
			<ArrowLeft className="size-3" /> {t("Oferty", "Offers")}
		</Link>
	);
	if (offer.isPending) return <Skeleton className="h-96 w-full rounded-xl" />;
	if (offer.isError)
		return (
			<>
				<PageHeader eyebrow={back} title={t("Oferta", "Offer")} />
				<ApiError error={offer.error} />
			</>
		);
	const o = offer.data;
	const isDraft = o.status === "DRAFT";
	const date = (iso: string) =>
		new Intl.DateTimeFormat(locale, { dateStyle: "long" }).format(new Date(`${iso}T00:00:00`));

	return (
		<>
			<PageHeader
				eyebrow={back}
				title={o.title}
				meta={
					<>
						<span className="font-mono text-xs text-muted">{o.number}</span>
						<Chip
							size="sm"
							variant="soft"
							color={offerStatusColor[o.status as OfferStatus] ?? "default"}
						>
							{offerStatusLabel(o.status, i18n)}
						</Chip>
						<span className="text-xs text-muted">{templateName(o, i18n)}</span>
					</>
				}
				actions={
					<>
						<a href={offerPdfUrl(o.id, lang)} target="_blank" rel="noreferrer">
							<Button variant="secondary">
								<FileText className="size-4" />
								{t("Podgląd PDF", "Preview PDF")}
							</Button>
						</a>
						<a href={offerPdfUrl(o.id, lang, true)} download>
							<Button variant="secondary">
								<FileDown className="size-4" />
								PDF
							</Button>
						</a>
						{isDraft && !editing ? (
							<Button variant="secondary" onPress={() => setEditing(true)}>
								<Pencil className="size-4" />
								{t("Edytuj", "Edit")}
							</Button>
						) : null}
						{!editing
							? NEXT_OFFER_STATUSES[o.status as OfferStatus].map((next) => (
									<Button
										key={next}
										variant={
											next === "REJECTED" ? "danger" : next === "DRAFT" ? "ghost" : "primary"
										}
										isPending={status.isPending && status.variables?.status === next}
										onPress={() =>
											status.mutate(
												{ status: next, rowVersion: o.rowVersion },
												{ onError: (e) => toast.danger(problemText(e, i18n)) },
											)
										}
									>
										{offerAction(next, i18n)}
									</Button>
								))
							: null}
						{isDraft && !editing ? (
							<Button
								variant="ghost"
								onPress={() => setConfirmDelete(true)}
								aria-label={t("Usuń szkic", "Delete draft")}
							>
								<Trash2 className="size-4" />
							</Button>
						) : null}
					</>
				}
			/>

			{editing ? (
				items.data ? (
					<DraftEditor offer={o} items={items.data} onDone={() => setEditing(false)} />
				) : (
					<Skeleton className="h-60 rounded-xl" />
				)
			) : (
				<div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_340px]">
					<div className="flex flex-col gap-6">
						{o.intro ? (
							<Card>
								<Card.Content>
									<p className="text-sm whitespace-pre-wrap text-foreground">{o.intro}</p>
								</Card.Content>
							</Card>
						) : null}
						<Card className="overflow-hidden p-0">
							{items.isPending ? (
								<Skeleton className="m-4 h-32 rounded-lg" />
							) : items.isError ? (
								<div className="p-4">
									<ApiError error={items.error} />
								</div>
							) : (
								<ItemsTable items={items.data} offer={o} />
							)}
						</Card>
						{o.terms ? (
							<Card>
								<Card.Header>
									<Card.Title>{t("Warunki", "Terms")}</Card.Title>
								</Card.Header>
								<Card.Content>
									<ul className="flex flex-col gap-1 text-sm text-foreground">
										{o.terms
											.split("\n")
											.filter((l) => l.trim())
											.map((l) => (
												<li key={l}>— {l}</li>
											))}
									</ul>
								</Card.Content>
							</Card>
						) : null}
					</div>
					<Card className="h-fit">
						<Card.Content>
							<InfoList
								items={[
									{
										label: t("Klient", "Client"),
										value: (
											<Link
												to="/clients/$clientId"
												params={{ clientId: o.clientId }}
												className="hover:underline"
											>
												{o.clientName}
											</Link>
										),
									},
									{ label: t("Ważna do", "Valid until"), value: date(o.validUntil) },
									{ label: t("Spółka podpisująca", "Signing company"), value: o.legalEntityName },
									{ label: t("Waluta", "Currency"), value: o.currency },
									{ label: t("Autor", "Author"), value: o.authorName },
									{
										label: t("Kontakt w PDF", "Contact in the PDF"),
										value:
											o.authorRole === "SALES"
												? [o.authorJobTitle, o.authorPhone, o.authorEmail]
														.filter(Boolean)
														.join(" · ") ||
													t(
														"uzupełnij swój kontakt w menu konta",
														"fill in your contact in the account menu",
													)
												: t(
														"dane firmy (autor nie jest sprzedawcą)",
														"the company's (the author is not a salesperson)",
													),
									},
								]}
							/>
						</Card.Content>
					</Card>
				</div>
			)}

			<ConfirmDialog
				isOpen={confirmDelete}
				onClose={() => setConfirmDelete(false)}
				error={remove.error}
				title={t("Usunąć szkic oferty?", "Delete the draft offer?")}
				description={`${o.number} · ${o.title}`}
				confirmLabel={t("Usuń", "Delete")}
				isPending={remove.isPending}
				onConfirm={() => remove.mutate({ id: o.id, rowVersion: o.rowVersion })}
			/>
		</>
	);
}

function ItemsTable({ items, offer }: { items: OfferItemResponse[]; offer: OfferResponse }) {
	const { t, locale } = useI18n();
	const num = (v: number) =>
		v.toLocaleString(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
	return (
		<div className="overflow-x-auto">
			<table className="w-full text-sm">
				<thead className="bg-surface-secondary font-mono text-[11px] tracking-[0.06em] text-muted uppercase">
					<tr>
						{[
							"#",
							t("Opis", "Description"),
							t("J.m.", "Unit"),
							t("Ilość", "Qty"),
							t("Cena netto", "Unit price"),
							"VAT",
							t("Netto", "Net"),
							t("Brutto", "Gross"),
						].map((h, i) => (
							<th
								key={h}
								className={`border-b border-separator px-3 py-2 ${i >= 3 ? "text-right" : "text-left"}`}
							>
								{h}
							</th>
						))}
					</tr>
				</thead>
				<tbody>
					{items.map((it) => (
						<tr key={it.lineNo} className="border-b border-separator/60">
							<td className="px-3 py-2 text-muted">{it.lineNo}</td>
							<td className="px-3 py-2">{it.description}</td>
							<td className="px-3 py-2 whitespace-nowrap">{it.unit}</td>
							<td className="figures px-3 py-2 text-right">
								{Number(it.quantity).toLocaleString(locale)}
							</td>
							<td className="figures px-3 py-2 text-right">{num(Number(it.unitPrice))}</td>
							<td className="figures px-3 py-2 text-right">{it.vatRate}%</td>
							<td className="figures px-3 py-2 text-right">{num(Number(it.net))}</td>
							<td className="figures px-3 py-2 text-right font-medium">{num(Number(it.gross))}</td>
						</tr>
					))}
				</tbody>
			</table>
			<dl className="ml-auto grid w-full max-w-sm grid-cols-2 gap-x-6 gap-y-1 p-4 text-sm">
				<dt className="text-muted">{t("Razem netto", "Total net")}</dt>
				<dd className="figures text-right whitespace-nowrap">
					{money(offer.totalNet, offer.currency, locale)}
				</dd>
				<dt className="text-muted">VAT</dt>
				<dd className="figures text-right whitespace-nowrap">
					{money(offer.totalVat, offer.currency, locale)}
				</dd>
				<dt className="font-medium">{t("Do zapłaty brutto", "Total gross")}</dt>
				<dd className="figures text-right font-display text-xl font-semibold whitespace-nowrap">
					{money(offer.totalGross, offer.currency, locale)}
				</dd>
			</dl>
		</div>
	);
}

interface Line {
	key: number;
	description: string;
	unit: string;
	quantity: string;
	unitPrice: string;
	vatRate: number;
}

/**
 * The draft in edit: texts, currency, validity and the lines. The sums under the lines are a preview; the procedure
 * checks every line and computes the totals the offer keeps.
 */
function DraftEditor({
	offer,
	items,
	onDone,
}: {
	offer: OfferResponse;
	items: OfferItemResponse[];
	onDone: () => void;
}) {
	const { t, locale } = useI18n();
	const [title, setTitle] = useState(offer.title);
	const [intro, setIntro] = useState(offer.intro);
	const [terms, setTerms] = useState(offer.terms);
	const [currency, setCurrency] = useState(offer.currency);
	const [validUntil, setValidUntil] = useState(offer.validUntil);
	const [company, setCompany] = useState(offer.legalEntityId);
	const [lines, setLines] = useState<Line[]>(
		items.map((it, i) => ({
			key: i,
			description: it.description,
			unit: it.unit,
			quantity: String(Number(it.quantity)),
			unitPrice: Number(it.unitPrice).toFixed(2),
			vatRate: it.vatRate,
		})),
	);
	const save = useUpdateOffer(offer.id, () => {
		toast.success(t("Zapisano ofertę", "Offer saved"));
		onDone();
	});
	const parse = (v: string) => Number(v.replace(/\s/g, "").replace(",", "."));
	const round2 = (v: number) => (Number.isFinite(v) ? Math.round(v * 100) / 100 : 0);
	// Rounded per line, as the procedure does.
	const lineNets = lines.map((l) => round2(parse(l.quantity) * parse(l.unitPrice)));
	const net = lineNets.reduce((sum, v) => sum + v, 0);
	const vat = lineNets.reduce((sum, v, i) => sum + round2((v * lines[i].vatRate) / 100), 0);
	const set = (key: number, change: Partial<Line>) =>
		setLines((ls) => ls.map((l) => (l.key === key ? { ...l, ...change } : l)));

	return (
		<Card>
			<Card.Content className="flex flex-col gap-5">
				<div className="grid gap-4 md:grid-cols-[minmax(0,1fr)_10rem_12rem]">
					<TextField value={title} onChange={setTitle} fullWidth>
						<Label>{t("Tytuł", "Title")}</Label>
						<Input maxLength={200} />
					</TextField>
					<Select value={currency} onChange={(k) => k && setCurrency(String(k))}>
						<Label>{t("Waluta", "Currency")}</Label>
						<Select.Trigger>
							<Select.Value />
							<Select.Indicator />
						</Select.Trigger>
						<Select.Popover>
							<ListBox>
								{CURRENCIES.map((c) => (
									<ListBox.Item key={c} id={c} textValue={c}>
										{c}
										<ListBox.ItemIndicator />
									</ListBox.Item>
								))}
							</ListBox>
						</Select.Popover>
					</Select>
					<DateInput
						label={t("Ważna do", "Valid until")}
						value={validUntil}
						onChange={setValidUntil}
					/>
					<CompanySelect
						label={t("Spółka podpisująca", "Signing company")}
						value={company}
						onChange={setCompany}
					/>
				</div>
				<TextField value={intro} onChange={setIntro} fullWidth>
					<Label>{t("Wstęp", "Introduction")}</Label>
					<TextArea rows={3} maxLength={2000} />
				</TextField>

				<div className="flex flex-col gap-2">
					<p className="text-sm font-medium">{t("Pozycje", "Lines")}</p>
					<div className="overflow-x-auto">
						<div className="grid min-w-[760px] grid-cols-[minmax(0,1fr)_6rem_6rem_8rem_6rem_2.5rem] gap-2 text-xs text-muted">
							<span>{t("Opis", "Description")}</span>
							<span>{t("J.m.", "Unit")}</span>
							<span>{t("Ilość", "Qty")}</span>
							<span>{t("Cena netto", "Unit price")}</span>
							<span>VAT</span>
							<span />
							{lines.map((l) => (
								<div key={l.key} className="contents">
									<TextField
										aria-label={t("Opis", "Description")}
										value={l.description}
										onChange={(v) => set(l.key, { description: v })}
									>
										<Input maxLength={400} />
									</TextField>
									<TextField
										aria-label={t("J.m.", "Unit")}
										value={l.unit}
										onChange={(v) => set(l.key, { unit: v })}
									>
										<Input maxLength={20} />
									</TextField>
									<TextField
										aria-label={t("Ilość", "Qty")}
										value={l.quantity}
										onChange={(v) => set(l.key, { quantity: v })}
									>
										<Input inputMode="decimal" />
									</TextField>
									<TextField
										aria-label={t("Cena netto", "Unit price")}
										value={l.unitPrice}
										onChange={(v) => set(l.key, { unitPrice: v })}
									>
										<Input inputMode="decimal" />
									</TextField>
									<Select
										aria-label="VAT"
										value={String(l.vatRate)}
										onChange={(k) => k != null && set(l.key, { vatRate: Number(k) })}
									>
										<Select.Trigger>
											<Select.Value />
											<Select.Indicator />
										</Select.Trigger>
										<Select.Popover>
											<ListBox>
												{VAT_RATES.map((r) => (
													<ListBox.Item key={r} id={String(r)} textValue={`${r}%`}>
														{r}%
														<ListBox.ItemIndicator />
													</ListBox.Item>
												))}
											</ListBox>
										</Select.Popover>
									</Select>
									<Button
										isIconOnly
										variant="ghost"
										aria-label={t("Usuń pozycję", "Remove line")}
										onPress={() => setLines((ls) => ls.filter((x) => x.key !== l.key))}
									>
										<X className="size-4" />
									</Button>
								</div>
							))}
						</div>
					</div>
					<div className="flex flex-wrap items-center justify-between gap-3">
						<Button
							size="sm"
							variant="secondary"
							onPress={() =>
								setLines((ls) => [
									...ls,
									{
										key: Math.max(0, ...ls.map((x) => x.key)) + 1,
										description: "",
										unit: t("szt.", "pcs"),
										quantity: "1",
										unitPrice: "0.00",
										vatRate: 23,
									},
								])
							}
						>
							<Plus className="size-3.5" />
							{t("Dodaj pozycję", "Add a line")}
						</Button>
						<span className="figures text-sm text-muted">
							{t("netto", "net")} {money(net, currency, locale)} · VAT{" "}
							{money(vat, currency, locale)} ·{" "}
							<strong className="text-foreground">{money(net + vat, currency, locale)}</strong>
						</span>
					</div>
				</div>

				<TextField value={terms} onChange={setTerms} fullWidth>
					<Label>{t("Warunki (jeden punkt w linii)", "Terms (one point per line)")}</Label>
					<TextArea rows={5} maxLength={4000} />
				</TextField>
				<ApiError error={save.error} />
				<div className="flex justify-end gap-2">
					<Button variant="secondary" onPress={onDone}>
						{t("Anuluj", "Cancel")}
					</Button>
					<Button
						isPending={save.isPending}
						onPress={() =>
							save.mutate({
								title,
								intro,
								terms,
								currency,
								validUntil,
								legalEntityId: company,
								rowVersion: offer.rowVersion,
								items: lines.map((l) => ({
									description: l.description,
									unit: l.unit,
									quantity: parse(l.quantity),
									unitPrice: parse(l.unitPrice),
									vatRate: l.vatRate,
								})),
							})
						}
					>
						{t("Zapisz szkic", "Save the draft")}
					</Button>
				</div>
			</Card.Content>
		</Card>
	);
}
