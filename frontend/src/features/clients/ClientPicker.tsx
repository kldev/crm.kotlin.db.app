import { Chip, ListBox, SearchField } from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { X } from "lucide-react";
import { useState } from "react";
import { searchClients } from "#/api/endpoints/clients/clients";
import { clientKeys } from "#/api/query-keys";
import { useDebouncedValue } from "#/hooks/useDebouncedValue";
import { useI18n } from "#/i18n";

type Ref = { id: number; name: string };

/** Pick a client by the start of its name; a salesperson finds only their own. Optional unless `required`. */
export function ClientPicker({
	value,
	onChange,
	required = false,
}: {
	value: Ref | undefined;
	onChange: (v: Ref | undefined) => void;
	required?: boolean;
}) {
	const { t } = useI18n();
	const [text, setText] = useState("");
	const prefix = useDebouncedValue(text.trim(), 300);
	const clients = useQuery({
		queryKey: clientKeys.list({ namePrefix: prefix || undefined, size: 6 }),
		queryFn: () => searchClients({ namePrefix: prefix || undefined, size: 6 }),
		enabled: prefix.length > 0,
	});
	return (
		<section className="flex flex-col gap-2">
			<p className="text-sm font-medium">
				{required ? t("Klient", "Client") : t("Klient (opcjonalnie)", "Client (optional)")}
			</p>
			{value ? (
				<Chip variant="soft" className="self-start">
					<span>{value.name}</span>
					<button
						type="button"
						aria-label={t("Bez klienta", "No client")}
						className="ml-1 text-muted hover:text-foreground"
						onClick={() => onChange(undefined)}
					>
						<X className="size-3" />
					</button>
				</Chip>
			) : null}
			<SearchField
				aria-label={t("Szukaj klienta", "Search clients")}
				value={text}
				onChange={setText}
				fullWidth
			>
				<SearchField.Group>
					<SearchField.SearchIcon />
					<SearchField.Input
						placeholder={t("Początek nazwy klienta…", "Start of the client's name…")}
					/>
					<SearchField.ClearButton />
				</SearchField.Group>
			</SearchField>
			{prefix && clients.data ? (
				<ListBox
					aria-label={t("Klienci", "Clients")}
					selectionMode="single"
					className="max-h-44 overflow-y-auto rounded-md border border-separator"
					onSelectionChange={(keys) => {
						const key = keys === "all" ? undefined : [...keys][0];
						const found = clients.data.items.find((c) => c.id === Number(key));
						if (found) {
							onChange({ id: found.id, name: found.name });
							setText("");
						}
					}}
				>
					{clients.data.items.map((c) => (
						<ListBox.Item key={c.id} id={c.id} textValue={c.name}>
							<span className="flex w-full justify-between gap-3">
								<span>{c.name}</span>
								<span className="text-xs text-muted">{c.city ?? ""}</span>
							</span>
						</ListBox.Item>
					))}
				</ListBox>
			) : null}
		</section>
	);
}
