import { toast } from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { forwardRef, useImperativeHandle, useState } from "react";
import type { UserResponse } from "#/api/models";
import { ApiError, FormDrawer } from "#/components/ui";
import { useAppForm } from "#/forms";
import { useI18n } from "#/i18n";
import { departmentsQuery, useSetUserDepartment } from "./hooks";

export interface DepartmentCommand {
	open: (user: UserResponse) => void;
}

const NONE = "__none";

/** An administrator puts a user in a department: the "my department" view of tasks groups by it (ADR-0014). */
export const DepartmentDrawer = forwardRef<DepartmentCommand>((_, ref) => {
	const [user, setUser] = useState<UserResponse | null>(null);
	useImperativeHandle(ref, () => ({ open: setUser }), []);
	if (!user) return null;
	return <Content key={user.id} user={user} onClose={() => setUser(null)} />;
});

function Content({ user, onClose }: { user: UserResponse; onClose: () => void }) {
	const { t } = useI18n();
	const departments = useQuery(departmentsQuery());
	const mutation = useSetUserDepartment(() => {
		toast.success(
			t(`Zapisano dział: ${user.displayName}`, `Department saved: ${user.displayName}`),
		);
		onClose();
	});
	const form = useAppForm({
		defaultValues: { department: user.department ?? NONE },
		onSubmit: ({ value }) =>
			mutation.mutate({
				userId: user.id,
				department: value.department === NONE ? null : value.department,
			}),
	});
	return (
		<FormDrawer
			title={user.displayName}
			description={t(
				"Dział, w którym pracuje: widok „Mój dział” w zadaniach i grupy na osi czasu.",
				"The department the user works in: the “My department” view of tasks and the timeline groups.",
			)}
			onClose={onClose}
			onSubmit={() => void form.handleSubmit()}
		>
			<FormDrawer.Body>
				<form.AppField name="department">
					{(f) => (
						<f.FormSelect
							label={t("Dział", "Department")}
							options={[
								{ id: NONE, label: t("Bez działu", "No department") },
								...(departments.data ?? []).map((d) => ({
									id: d.name,
									label: d.name,
									description: t(`${d.users} os.`, `${d.users} people`),
								})),
							]}
						/>
					)}
				</form.AppField>
				<ApiError error={mutation.error} />
			</FormDrawer.Body>
			<FormDrawer.Footer isPending={mutation.isPending} />
		</FormDrawer>
	);
}
