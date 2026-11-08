import { Alert } from "@heroui/react";
import { problemMessage } from "#/api/mutator";

/** The message of a failed request (the procedure's THROW text for 4xx), or nothing. */
export function ApiError({
	error,
	title = "That did not work",
}: {
	error: unknown;
	title?: string;
}) {
	if (!error) return null;
	return (
		<Alert status="danger">
			<Alert.Indicator />
			<Alert.Content>
				<Alert.Title>{title}</Alert.Title>
				<Alert.Description>{problemMessage(error)}</Alert.Description>
			</Alert.Content>
		</Alert>
	);
}
