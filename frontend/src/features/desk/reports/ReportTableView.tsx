import { Button, Dropdown, Label, toast } from "@heroui/react";
import { useNavigate } from "@tanstack/react-router";
import { Copy, EllipsisVertical, FileDown, SquareArrowOutUpRight } from "lucide-react";
import { findTicket } from "#/api/endpoints/desk/desk";
import type { ReportTableResponse } from "#/api/models";
import { TIME_ZONE, useI18n } from "#/i18n";
import { problemText } from "#/i18n/problems";

/**
 * A report table as the exports write it (ADR-0010): typed cells formatted for the reader, a second header row when
 * columns are grouped (the periods of the agents' report), totals in bold. Wide reports scroll sideways with the first
 * column in place. When the rows are tickets (the first column is the number), a menu in front of each row opens it.
 */
export function ReportTableView({ table }: { table: ReportTableResponse }) {
	const i18n = useI18n();
	const { t, locale } = i18n;
	const tickets = table.columns[0]?.key === "number";
	// With the menu in front, the first data column sticks right after it.
	const firstCell = tickets ? STICKY_CELL_AFTER_MENU : STICKY_CELL;
	const firstHead = tickets ? STICKY_HEAD_AFTER_MENU : STICKY_HEAD;
	const grouped = table.columns.some((c) => c.group);
	const groups: { label: string; span: number }[] = [];
	for (const c of table.columns) {
		const label = c.group ?? "";
		const last = groups.at(-1);
		if (last && last.label === label && label !== "") last.span += 1;
		else groups.push({ label, span: 1 });
	}
	const format = (kind: string, value: string | null | undefined) => {
		if (value == null || value === "") return "";
		switch (kind) {
			case "DATETIME":
				return new Intl.DateTimeFormat(locale, {
					timeZone: TIME_ZONE,
					dateStyle: "short",
					timeStyle: "short",
				}).format(new Date(value));
			case "DATE":
				return new Intl.DateTimeFormat(locale, { dateStyle: "short" }).format(
					new Date(`${value}T00:00:00`),
				);
			case "AMOUNT":
				return Number(value).toLocaleString(locale, {
					minimumFractionDigits: 2,
					maximumFractionDigits: 2,
				});
			default:
				return value;
		}
	};
	const numeric = (kind: string) => kind === "NUMBER" || kind === "AMOUNT";

	if (table.rows.length === 0)
		return (
			<p className="p-6 text-sm text-muted">
				{t("Brak zgłoszeń w tym okresie.", "No tickets in this period.")}
			</p>
		);
	return (
		<div className="overflow-x-auto">
			{/* Separate borders: with collapsed ones the sticky first column would lose its lines while scrolling. */}
			<table className="w-full min-w-max border-separate border-spacing-0 text-sm">
				<thead className="bg-surface-secondary font-mono text-[11px] tracking-[0.06em] text-muted uppercase">
					{grouped ? (
						<tr>
							{tickets ? <th className={`border-b border-separator ${MENU_HEAD}`} /> : null}
							{groups.map((g, i) => (
								<th
									key={`${g.label}-${i}`}
									colSpan={g.span}
									className={`border-b border-separator px-3 py-2 text-center ${i === 0 && g.span === 1 ? firstHead : ""}`}
								>
									{g.label}
								</th>
							))}
						</tr>
					) : null}
					<tr>
						{tickets ? (
							<th className={`border-b border-separator ${MENU_HEAD}`}>
								<span className="sr-only">{t("Akcje", "Actions")}</span>
							</th>
						) : null}
						{table.columns.map((c, i) => (
							<th
								key={c.key}
								className={`border-b border-separator px-3 py-2 whitespace-nowrap ${numeric(c.kind) ? "text-right" : "text-left"} ${i === 0 ? firstHead : ""}`}
							>
								{c.label}
							</th>
						))}
					</tr>
				</thead>
				<tbody>
					{table.rows.map((row, r) => (
						<tr key={`${r}-${row[0]}`} className="group">
							{tickets ? (
								<td
									className={`border-b border-separator/60 py-1 group-hover:bg-surface-secondary ${MENU_CELL}`}
								>
									<TicketMenu
										number={row[0] ?? ""}
										onError={(e) => toast.danger(problemText(e, i18n))}
									/>
								</td>
							) : null}
							{row.map((cell, i) => (
								<td
									key={table.columns[i]?.key ?? i}
									className={`border-b border-separator/60 px-3 py-2 align-top group-hover:bg-surface-secondary ${numeric(table.columns[i]?.kind ?? "") ? "figures text-right" : ""} ${
										table.columns[i]?.key === "title" ? "min-w-64" : "whitespace-nowrap"
									} ${i === 0 ? firstCell : ""}`}
								>
									{format(table.columns[i]?.kind ?? "TEXT", cell)}
								</td>
							))}
						</tr>
					))}
					{table.totals ? (
						<tr className="font-semibold">
							{tickets ? <td className={MENU_CELL} /> : null}
							{table.totals.map((cell, i) => (
								<td
									key={table.columns[i]?.key ?? i}
									className={`px-3 py-2 ${numeric(table.columns[i]?.kind ?? "") ? "figures text-right" : ""} ${i === 0 ? firstCell : ""}`}
								>
									{format(table.columns[i]?.kind ?? "TEXT", cell)}
								</td>
							))}
						</tr>
					) : null}
				</tbody>
			</table>
		</div>
	);
}

/**
 * The first column stays in place while a wide report scrolls sideways, so every row keeps its name. It needs its own
 * opaque background (the row's hover included) and a hairline on the right where the other columns slide under it.
 */
export const STICKY_CELL =
	"sticky left-0 z-[1] bg-surface shadow-[inset_-1px_0_0_var(--obs-border)] group-hover:bg-surface-secondary";
export const STICKY_HEAD =
	"sticky left-0 z-[2] bg-surface-secondary shadow-[inset_-1px_0_0_var(--obs-border)]";
const STICKY_CELL_AFTER_MENU =
	"sticky left-11 z-[1] bg-surface shadow-[inset_-1px_0_0_var(--obs-border)] group-hover:bg-surface-secondary";
const STICKY_HEAD_AFTER_MENU =
	"sticky left-11 z-[2] bg-surface-secondary shadow-[inset_-1px_0_0_var(--obs-border)]";
const MENU_CELL =
	"sticky left-0 z-[1] w-11 min-w-11 bg-surface px-1 text-center group-hover:bg-surface-secondary";
const MENU_HEAD = "sticky left-0 z-[2] w-11 min-w-11 bg-surface-secondary";

/** The row menu of a ticket report: the ticket's page (found by its public number) and the number to the clipboard. */
function TicketMenu({ number, onError }: { number: string; onError: (error: unknown) => void }) {
	const { t } = useI18n();
	const navigate = useNavigate();
	return (
		<Dropdown>
			<Dropdown.Trigger>
				<Button
					isIconOnly
					size="sm"
					variant="ghost"
					aria-label={t(`Akcje: ${number}`, `Actions for ${number}`)}
				>
					<EllipsisVertical className="size-4" />
				</Button>
			</Dropdown.Trigger>
			<Dropdown.Popover placement="bottom start">
				<Dropdown.Menu
					onAction={(key) => {
						if (key === "open")
							findTicket(number)
								.then((ticket) =>
									navigate({ to: "/desk/tickets/$ticketId", params: { ticketId: ticket.id } }),
								)
								.catch(onError);
						if (key === "copy")
							void navigator.clipboard
								.writeText(number)
								.then(() => toast.success(t(`Skopiowano ${number}`, `Copied ${number}`)));
					}}
				>
					<Dropdown.Item
						id="open"
						textValue={t("Pokaż szczegóły zgłoszenia", "Show ticket details")}
					>
						<SquareArrowOutUpRight className="size-4" />
						<Label>{t("Pokaż szczegóły zgłoszenia", "Show ticket details")}</Label>
					</Dropdown.Item>
					<Dropdown.Item id="copy" textValue={t("Kopiuj numer", "Copy the number")}>
						<Copy className="size-4" />
						<Label>{t("Kopiuj numer", "Copy the number")}</Label>
					</Dropdown.Item>
				</Dropdown.Menu>
			</Dropdown.Popover>
		</Dropdown>
	);
}

/** CSV, XLSX and PDF of the same table: plain links, the session cookie authorises the download. */
export function ExportButtons({ href }: { href: (format: "csv" | "xlsx" | "pdf") => string }) {
	return (
		<div className="flex gap-2">
			{(["xlsx", "pdf", "csv"] as const).map((f) => (
				<a key={f} href={href(f)} download>
					<Button size="sm" variant="secondary">
						<FileDown className="size-3.5" />
						{f.toUpperCase()}
					</Button>
				</a>
			))}
		</div>
	);
}
