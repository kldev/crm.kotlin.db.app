import { Label, ListBox, Select } from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { useI18n } from "#/i18n";
import { legalEntitiesQuery, pickable } from "./hooks";

/** One of the group's trading companies (ADR-0016), plus the current one even when it has closed since. */
export function CompanySelect({
	value,
	onChange,
	label,
	className,
	isDisabled,
}: {
	value: number | undefined;
	onChange: (id: number) => void;
	label?: string;
	className?: string;
	isDisabled?: boolean;
}) {
	const { t } = useI18n();
	const entities = useQuery(legalEntitiesQuery());
	return (
		<Select
			className={className}
			value={value ?? null}
			onChange={(key) => key != null && onChange(Number(key))}
			isDisabled={isDisabled}
			placeholder={t("Wybierz spółkę…", "Choose a company…")}
		>
			<Label>{label ?? t("Spółka", "Company")}</Label>
			<Select.Trigger>
				<Select.Value />
				<Select.Indicator />
			</Select.Trigger>
			<Select.Popover>
				<ListBox>
					{pickable(entities.data, value).map((e) => (
						<ListBox.Item key={e.id} id={e.id} textValue={e.name}>
							<div className="flex flex-col">
								<span>{e.name}</span>
								<span className="text-xs text-muted">{e.legalName}</span>
							</div>
							<ListBox.ItemIndicator />
						</ListBox.Item>
					))}
				</ListBox>
			</Select.Popover>
		</Select>
	);
}
