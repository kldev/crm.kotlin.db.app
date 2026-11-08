import { queryOptions, useMutation, useQueryClient } from "@tanstack/react-query";
import {
	addDealActivity,
	getDeal,
	listActivityTypes,
	listDealActivities,
	setDealNextStep,
} from "#/api/endpoints/deals/deals";
import { listFollowUps, listWithoutNextStep } from "#/api/endpoints/sales/sales";
import { taskAgenda } from "#/api/endpoints/tasks/tasks";
import type { ActivityRequest, DealResponse, NextStepRequest } from "#/api/models";
import { dealKeys, taskKeys } from "#/api/query-keys";

export const dealQuery = (id: number) =>
	queryOptions({ queryKey: dealKeys.detail(id), queryFn: () => getDeal(id) });

export const activityTypesQuery = () =>
	queryOptions({
		queryKey: dealKeys.activityTypes(),
		queryFn: () => listActivityTypes(),
		staleTime: Number.POSITIVE_INFINITY,
	});

export const dealActivitiesQuery = (id: number) =>
	queryOptions({ queryKey: dealKeys.activities(id), queryFn: () => listDealActivities(id) });

export const followUpsQuery = (until: string, scope: string) =>
	queryOptions({
		queryKey: dealKeys.followUps({ until, scope }),
		queryFn: () => listFollowUps({ until, scope }),
	});

export const withoutNextStepQuery = (scope: string) =>
	queryOptions({
		queryKey: dealKeys.withoutNextStep(scope),
		queryFn: () => listWithoutNextStep({ scope }),
	});

export const agendaQuery = (until: string, doneSince: string) =>
	queryOptions({
		queryKey: taskKeys.agenda({ until, doneSince }),
		queryFn: () => taskAgenda({ until, doneSince }),
	});

/**
 * A write on a deal refreshes the deals (the board, the deal, "my day") and the tasks: finishing a task of a deal
 * logs on the deal, and a deal's activity shows on the cards.
 */
function useSalesMutation<TVars, TResult>(
	fn: (vars: TVars) => Promise<TResult>,
	onSuccess?: (r: TResult) => void,
) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: fn,
		onSuccess: async (result) => {
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: dealKeys.all }),
				queryClient.invalidateQueries({ queryKey: taskKeys.all }),
			]);
			onSuccess?.(result);
		},
	});
}

export const useAddActivity = (dealId: number, onSuccess?: () => void) =>
	useSalesMutation((body: ActivityRequest) => addDealActivity(dealId, body), onSuccess);

export const useSetNextStep = (dealId: number, onSuccess?: (deal: DealResponse) => void) =>
	useSalesMutation((body: NextStepRequest) => setDealNextStep(dealId, body), onSuccess);

/** The end of today, or of this week (Sunday), in the browser's calendar - the horizon of "my day". */
export function horizon(range: "day" | "week"): { until: string; untilDay: string } {
	const now = new Date();
	const end = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59);
	if (range === "week") end.setDate(end.getDate() + ((7 - end.getDay()) % 7));
	const day = `${end.getFullYear()}-${String(end.getMonth() + 1).padStart(2, "0")}-${String(end.getDate()).padStart(2, "0")}`;
	return { until: end.toISOString(), untilDay: day };
}

/** Midnight today, as an instant: tasks finished since then are "done today". */
export const startOfToday = () => {
	const now = new Date();
	return new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();
};
