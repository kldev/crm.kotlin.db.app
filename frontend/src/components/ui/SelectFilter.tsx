import { Label, ListBox, Select } from "@heroui/react";

const ANY = "__any";

/** A toolbar filter: "Any" clears it. The value lives in the URL, so it is a string or undefined. */
export function SelectFilter({
	label,
	value,
	options,
	onChange,
	className = "w-full sm:w-44",
}: {
	label: string;
	value: string | undefined;
	options: { id: string; label: string }[];
	onChange: (value: string | undefined) => void;
	className?: string;
}) {
	return (
		<Select
			className={className}
			value={value ?? ANY}
			onChange={(key) => onChange(key == null || key === ANY ? undefined : String(key))}
		>
			<Label className="sr-only">{label}</Label>
			<Select.Trigger>
				<span className="mr-1 text-xs text-muted">{label}:</span>
				<Select.Value />
				<Select.Indicator />
			</Select.Trigger>
			<Select.Popover>
				<ListBox>
					<ListBox.Item id={ANY} textValue="Any">
						Any
						<ListBox.ItemIndicator />
					</ListBox.Item>
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
