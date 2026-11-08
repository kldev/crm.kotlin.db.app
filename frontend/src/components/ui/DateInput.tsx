import { Calendar, DateField, DatePicker, Description, FieldError, Label } from "@heroui/react";
import { type CalendarDate, parseDate } from "@internationalized/date";
import { useI18n } from "#/i18n";

/** "2026-11-08" -> CalendarDate; anything else (empty, half typed) -> null. */
function toCalendarDate(value: string | null | undefined): CalendarDate | null {
	if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
	try {
		return parseDate(value);
	} catch {
		return null;
	}
}

/**
 * A date the app's way instead of the browser's native picker: typed segment by segment in the user's format
 * (dd.mm.rrrr in Polish), or picked in a calendar that starts on Monday. The value stays the API's ISO day
 * ("2026-11-08", "" when empty), so forms and URLs keep plain strings.
 */
export function DateInput({
	label,
	value,
	onChange,
	onBlur,
	description,
	errorMessage,
	isInvalid,
	isDisabled,
	isRequired,
	minValue,
	maxValue,
	name,
	className,
	hideLabel,
}: {
	label: string;
	value: string | null | undefined;
	onChange: (value: string) => void;
	onBlur?: () => void;
	description?: string;
	errorMessage?: string;
	isInvalid?: boolean;
	isDisabled?: boolean;
	isRequired?: boolean;
	minValue?: string;
	maxValue?: string;
	name?: string;
	className?: string;
	hideLabel?: boolean;
}) {
	const { t } = useI18n();
	return (
		<DatePicker
			className={className}
			name={name}
			value={toCalendarDate(value)}
			onChange={(date) => onChange(date ? date.toString() : "")}
			onBlur={onBlur}
			isInvalid={isInvalid}
			isDisabled={isDisabled}
			isRequired={isRequired}
			minValue={toCalendarDate(minValue) ?? undefined}
			maxValue={toCalendarDate(maxValue) ?? undefined}
			// zod and the procedures are the authority; React Aria only marks the field
			validationBehavior="aria"
			firstDayOfWeek="mon"
		>
			<Label className={hideLabel ? "sr-only" : undefined}>{label}</Label>
			<DateField.Group fullWidth>
				<DateField.Input>{(segment) => <DateField.Segment segment={segment} />}</DateField.Input>
				<DateField.Suffix>
					<DatePicker.Trigger aria-label={t("Otwórz kalendarz", "Open the calendar")}>
						<DatePicker.TriggerIndicator />
					</DatePicker.Trigger>
				</DateField.Suffix>
			</DateField.Group>
			{description ? <Description>{description}</Description> : null}
			<FieldError>{errorMessage}</FieldError>
			<DatePicker.Popover>
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
			</DatePicker.Popover>
		</DatePicker>
	);
}
