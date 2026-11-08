import { Chip } from "@heroui/react";
import { type ClientStatus, clientStatusColor, clientStatusLabel } from "#/features/types";
import { useI18n } from "#/i18n";

export function ClientStatusChip({ status }: { status: string }) {
	const i18n = useI18n();
	return (
		<Chip size="sm" variant="soft" color={clientStatusColor[status as ClientStatus] ?? "default"}>
			{clientStatusLabel(status, i18n)}
		</Chip>
	);
}
