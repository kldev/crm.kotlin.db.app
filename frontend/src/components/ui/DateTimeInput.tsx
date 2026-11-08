import { Calendar, DateField, DatePicker, FieldError, Label, TimeField } from "@heroui/react";
import { parseAbsolute, type ZonedDateTime } from "@internationalized/date";
import { TIME_ZONE, useI18n } from "#/i18n";

function toZoned(value: string | null | undefined): ZonedDateTime | null {
	if (!value) return null;
	try {
		return parseAbsolute(value, TIME_ZONE);
	} catch {
		return null;
	}
}

/**
 * A moment - a day and an hour - in the app's own picker: typed (dd.mm.rrrr, gg:mm) or picked in a calendar with the
 * time under it. Shown in Warsaw time like every time in the app; the value is the instant in ISO ("…Z"), "" when empty.
 */
export function DateTimeInput({
	label,
	value,
	onChange,
	errorMessage,
	isInvalid,
	className,
}: {
	label: string;
	value: string | null | undefined;
	onChange: (value: string) => void;
	errorMessage?: string;
	isInvalid?: boolean;
	className?: string;
}) {
	const { t } = useI18n();
	return (
		<DatePicker
			className={className}
			value={toZoned(value)}
			onChange={(v) => onChange(v ? v.toAbsoluteString() : "")}
			granularity="minute"
			hourCycle={24}
			hideTimeZone
			isInvalid={isInvalid}
			validationBehavior="aria"
			firstDayOfWeek="mon"
		>
			{({ state }) => (
				<>
					<Label>{label}</Label>
					<DateField.Group fullWidth>
						<DateField.Input>
							{(segment) => <DateField.Segment segment={segment} />}
						</DateField.Input>
						<DateField.Suffix>
							<DatePicker.Trigger aria-label={t("Otwórz kalendarz", "Open the calendar")}>
								<DatePicker.TriggerIndicator />
							</DatePicker.Trigger>
						</DateField.Suffix>
					</DateField.Group>
					<FieldError>{errorMessage}</FieldError>
					<DatePicker.Popover className="flex flex-col gap-3">
						<Calendar aria-label={label} firstDayOfWeek="mon">
							<Calendar.Header>
								<Calendar.YearPickerTrigger>
									<Calendar.YearPickerTriggerHeading />
									<Calendar.YearPickerTriggerIndicator />
								</Calendar.YearPickerTrigger>
								<Calendar.NavButton slot="previous" />
								<Calendar.NavButton slot="next" />
							</Calendar.Header>
							<Calendar.Grid>
								<Calendar.GridHeader>
									{(day) => <Calendar.HeaderCell>{day}</Calendar.HeaderCell>}
								</Calendar.GridHeader>
								<Calendar.GridBody>{(date) => <Calendar.Cell date={date} />}</Calendar.GridBody>
							</Calendar.Grid>
							<Calendar.YearPickerGrid>
								<Calendar.YearPickerGridBody>
									{({ year }) => <Calendar.YearPickerCell year={year} />}
								</Calendar.YearPickerGridBody>
							</Calendar.YearPickerGrid>
						</Calendar>
						<div className="flex items-center justify-between gap-3">
							<Label>{t("Godzina", "Time")}</Label>
							<TimeField
								aria-label={t("Godzina", "Time")}
								granularity="minute"
								hourCycle={24}
								hideTimeZone
								value={state.timeValue}
								onChange={(v) => v && state.setTimeValue(v)}
							>
								<TimeField.Group variant="secondary">
									<TimeField.Input>
										{(segment) => <TimeField.Segment segment={segment} />}
									</TimeField.Input>
								</TimeField.Group>
							</TimeField>
						</div>
					</DatePicker.Popover>
				</>
			)}
		</DatePicker>
	);
}
