import { keepPreviousData, queryOptions, useMutation, useQueryClient } from "@tanstack/react-query";
import {
	createTask,
	deleteTask,
	listDepartments,
	listTasks,
	setTaskDone,
	setUserDepartment,
	updateTask,
} from "#/api/endpoints/tasks/tasks";
import type { ListTasksParams, TaskRequest, TaskResponse } from "#/api/models";
import { taskKeys, userKeys } from "#/api/query-keys";

/** The tasks overlapping a window of days; the previous window stays on screen while the next one loads. */
export const tasksQuery = (params: ListTasksParams) =>
	queryOptions({
		queryKey: taskKeys.window(params),
		queryFn: ({ signal }) => listTasks(params, { signal }),
		placeholderData: keepPreviousData,
	});

export const departmentsQuery = () =>
	queryOptions({
		queryKey: taskKeys.departments(),
		queryFn: () => listDepartments(),
		staleTime: 5 * 60_000,
	});

/** Every task write invalidates the whole area, then calls onSuccess. */
function useTaskMutation<TVars, TResult>(
	fn: (vars: TVars) => Promise<TResult>,
	onSuccess?: (result: TResult) => void,
) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: fn,
		onSuccess: async (result) => {
			await queryClient.invalidateQueries({ queryKey: taskKeys.all });
			onSuccess?.(result);
		},
	});
}

type OnTask = (task: TaskResponse) => void;

export const useCreateTask = (onSuccess?: OnTask) =>
	useTaskMutation((body: TaskRequest) => createTask(body), onSuccess);

export const useUpdateTask = (id: number, onSuccess?: OnTask) =>
	useTaskMutation((body: TaskRequest) => updateTask(id, body), onSuccess);

export const useSetTaskDone = (onSuccess?: OnTask) =>
	useTaskMutation(
		(v: { id: number; done: boolean; rowVersion: string }) =>
			setTaskDone(v.id, { done: v.done, rowVersion: v.rowVersion }),
		onSuccess,
	);

export const useDeleteTask = (onSuccess?: () => void) =>
	useTaskMutation(
		(v: { id: number; rowVersion: string }) => deleteTask(v.id, { rowVersion: v.rowVersion }),
		onSuccess,
	);

/** An administrator moves a user to a department: users and the task views both show it. */
export function useSetUserDepartment(onSuccess?: () => void) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (v: { userId: number; department: string | null }) =>
			setUserDepartment(v.userId, { department: v.department }),
		onSuccess: async () => {
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: userKeys.all }),
				queryClient.invalidateQueries({ queryKey: taskKeys.all }),
			]);
			onSuccess?.();
		},
	});
}
