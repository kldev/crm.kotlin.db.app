import { Chip } from "@heroui/react";
import { type Stage, stageColor, stageLabel } from "#/features/types";
import { useI18n } from "#/i18n";

export function StageChip({ stage, size = "sm" }: { stage: string; size?: "sm" | "md" | "lg" }) {
	const i18n = useI18n();
	return (
		<Chip size={size} variant="soft" color={stageColor[stage as Stage] ?? "default"}>
			{stageLabel(stage, i18n)}
		</Chip>
	);
}

export function DueDate({ date, overdue }: { date: string; overdue: boolean }) {
	const { t } = useI18n();
	return (
		<span
			className={`figures text-xs ${overdue ? "font-semibold text-danger" : "text-foreground"}`}
		>
			{date}
			{overdue ? ` · ${t("po terminie", "overdue")}` : ""}
		</span>
	);
}
