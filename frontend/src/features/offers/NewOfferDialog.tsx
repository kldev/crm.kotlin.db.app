import { Button, ListBox, Modal, SearchField } from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { HardHat, Laptop, type LucideIcon, UsersRound } from "lucide-react";
import { forwardRef, useImperativeHandle, useState } from "react";
import { searchClients } from "#/api/endpoints/clients/clients";
import type { OfferResponse } from "#/api/models";
import { clientKeys } from "#/api/query-keys";
import { ApiError } from "#/components/ui";
import { useDebouncedValue } from "#/hooks/useDebouncedValue";
import { useI18n } from "#/i18n";
import { offerTemplatesQuery, useCreateOffer } from "./hooks";
import { templateName } from "./types";

export interface NewOfferCommand {
	/** Open the dialog, optionally for a known client (the client's page). */
	open: (client?: { id: number; name: string }) => void;
}

const ICONS: Record<string, LucideIcon> = {
	CONSTRUCTION: HardHat,
	IT: Laptop,
	OUTSOURCING: UsersRound,
};

/**
 * A new offer: the client (a salesperson finds only their own) and one of the three templates. The template's texts
 * and lines are copied into the draft, in the user's language, and edited there.
 */
export const NewOfferDialog = forwardRef<
	NewOfferCommand,
	{ onCreated: (offer: OfferResponse) => void }
>(({ onCreated }, ref) => {
	const [open, setOpen] = useState<{ client?: { id: number; name: string } } | null>(null);
	useImperativeHandle(ref, () => ({ open: (client) => setOpen({ client }) }), []);
	if (!open) return null;
	return (
		<Content
			initialClient={open.client}
			onClose={() => setOpen(null)}
			onCreated={(o) => {
				setOpen(null);
				onCreated(o);
			}}
		/>
	);
});

function Content({
	initialClient,
	onClose,
	onCreated,
}: {
	initialClient?: { id: number; name: string };
	onClose: () => void;
	onCreated: (offer: OfferResponse) => void;
}) {
	const i18n = useI18n();
	const { t, lang } = i18n;
	const templates = useQuery(offerTemplatesQuery());
	const [client, setClient] = useState(initialClient);
	const [template, setTemplate] = useState<string>("IT");
	const [text, setText] = useState("");
	const prefix = useDebouncedValue(text.trim(), 300);
	const clients = useQuery({
		queryKey: clientKeys.list({ namePrefix: prefix || undefined, size: 8 }),
		queryFn: () => searchClients({ namePrefix: prefix || undefined, size: 8 }),
		enabled: !initialClient,
	});
	const create = useCreateOffer(onCreated);
	return (
		<Modal>
			<Modal.Backdrop isOpen onOpenChange={(o) => !o && onClose()}>
				<Modal.Container size="lg">
					<Modal.Dialog>
						<Modal.CloseTrigger />
						<Modal.Header>
							<Modal.Heading className="font-display text-2xl">
								{t("Nowa oferta", "New offer")}
							</Modal.Heading>
						</Modal.Header>
						<Modal.Body>
							<div className="flex flex-col gap-5">
								<section className="flex flex-col gap-2">
									<p className="text-sm font-medium">{t("Klient", "Client")}</p>
									{initialClient ? (
										<p className="text-sm">{initialClient.name}</p>
									) : (
										<>
											<SearchField
												aria-label={t("Szukaj klienta", "Search clients")}
												value={text}
												onChange={setText}
												fullWidth
											>
												<SearchField.Group>
													<SearchField.SearchIcon />
													<SearchField.Input
														placeholder={t(
															"Początek nazwy klienta…",
															"Start of the client's name…",
														)}
													/>
													<SearchField.ClearButton />
												</SearchField.Group>
											</SearchField>
											<ListBox
												aria-label={t("Klienci", "Clients")}
												selectionMode="single"
												className="max-h-52 overflow-y-auto rounded-md border border-separator"
												selectedKeys={client ? new Set([client.id]) : new Set()}
												onSelectionChange={(keys) => {
													const key = keys === "all" ? undefined : [...keys][0];
													const found = clients.data?.items.find((c) => c.id === Number(key));
													setClient(found ? { id: found.id, name: found.name } : undefined);
												}}
											>
												{(clients.data?.items ?? []).map((c) => (
													<ListBox.Item key={c.id} id={c.id} textValue={c.name}>
														<span className="flex w-full justify-between gap-3">
															<span>{c.name}</span>
															<span className="text-xs text-muted">{c.city ?? ""}</span>
														</span>
														<ListBox.ItemIndicator />
													</ListBox.Item>
												))}
											</ListBox>
										</>
									)}
								</section>
								<section className="flex flex-col gap-2">
									<p className="text-sm font-medium">{t("Szablon", "Template")}</p>
									<div className="grid gap-3 sm:grid-cols-3">
										{(templates.data ?? []).map((tpl) => {
											const Icon = ICONS[tpl.key] ?? Laptop;
											const chosen = tpl.key === template;
											return (
												<button
													key={tpl.key}
													type="button"
													aria-pressed={chosen}
													onClick={() => setTemplate(tpl.key)}
													className={`flex flex-col items-start gap-2 rounded-xl border p-4 text-left transition-colors ${
														chosen
															? "border-accent bg-accent-soft ring-1 ring-accent"
															: "border-separator hover:bg-surface-secondary"
													}`}
												>
													<span className="flex size-9 items-center justify-center rounded-lg bg-surface-secondary text-ink">
														<Icon className="size-4" strokeWidth={1.75} />
													</span>
													<span className="text-sm font-medium">{templateName(tpl, i18n)}</span>
													<span className="text-xs text-muted">
														{lang === "pl" ? tpl.titlePl : tpl.titleEn} ·{" "}
														{t(`ważna ${tpl.validityDays} dni`, `valid ${tpl.validityDays} days`)}
													</span>
												</button>
											);
										})}
									</div>
								</section>
								<ApiError error={create.error} />
							</div>
						</Modal.Body>
						<Modal.Footer>
							<Button slot="close" variant="secondary">
								{t("Anuluj", "Cancel")}
							</Button>
							<Button
								isDisabled={!client}
								isPending={create.isPending}
								onPress={() =>
									client && create.mutate({ clientId: client.id, templateKey: template, lang })
								}
							>
								{t("Utwórz szkic", "Create a draft")}
							</Button>
						</Modal.Footer>
					</Modal.Dialog>
				</Modal.Container>
			</Modal.Backdrop>
		</Modal>
	);
}
