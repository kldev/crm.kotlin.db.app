import { Chip, ListBox, SearchField } from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { listDeskAgents } from "#/api/endpoints/desk/desk";
import { deskKeys } from "#/api/query-keys";
import { useDebouncedValue } from "#/hooks/useDebouncedValue";
import { useI18n } from "#/i18n";

type Ref = { id: number; name: string };

/** Search people (any user) by name; the chosen one stays shown above the results. */
export function PersonPicker({
	value,
	onChange,
	label,
}: {
	value: Ref | undefined;
	onChange: (v: Ref) => void;
	label?: string;
}) {
	const { t } = useI18n();
	const [text, setText] = useState("");
	const search = useDebouncedValue(text.trim(), 300);
	const people = useQuery({
		queryKey: deskKeys.agents({ search: search || undefined, size: 6 }),
		queryFn: () => listDeskAgents({ search: search || undefined, size: 6 }),
		enabled: search.length > 0,
	});
	return (
		<section className="flex flex-col gap-2">
			<p className="text-sm font-medium">{label ?? t("Osoba", "Person")}</p>
			{value ? (
				<Chip variant="soft" className="self-start">
					{value.name}
				</Chip>
			) : null}
			<SearchField
				aria-label={t("Szukaj osoby", "Search people")}
				value={text}
				onChange={setText}
				fullWidth
			>
				<SearchField.Group>
					<SearchField.SearchIcon />
					<SearchField.Input placeholder={t("Zmień: imię lub nazwisko…", "Change: a name…")} />
					<SearchField.ClearButton />
				</SearchField.Group>
			</SearchField>
			{search && people.data ? (
				<ListBox
					aria-label={t("Osoby", "People")}
					selectionMode="single"
					className="max-h-44 overflow-y-auto rounded-md border border-separator"
					onSelectionChange={(keys) => {
						const key = keys === "all" ? undefined : [...keys][0];
						const found = people.data.items.find((p) => p.id === Number(key));
						if (found) {
							onChange({ id: found.id, name: found.displayName });
							setText("");
						}
					}}
				>
					{people.data.items.map((p) => (
						<ListBox.Item key={p.id} id={p.id} textValue={p.displayName}>
							<span className="flex w-full justify-between gap-3">
								<span>{p.displayName}</span>
								<span className="font-mono text-xs text-muted">{p.login}</span>
							</span>
						</ListBox.Item>
					))}
				</ListBox>
			) : null}
		</section>
	);
}
