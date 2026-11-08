import { keepPreviousData, queryOptions, useMutation, useQueryClient } from "@tanstack/react-query";
import {
	createDeal,
	dealBoard,
	dealBoardSummary,
	deleteDeal,
	listDealStages,
	moveDeal,
	updateDeal,
} from "#/api/endpoints/deals/deals";
import type {
	CreateDealRequest,
	DealBoardParams,
	DealResponse,
	MoveDealRequest,
	UpdateDealRequest,
} from "#/api/models";
import { dealKeys } from "#/api/query-keys";

export const dealStagesQuery = () =>
	queryOptions({
		queryKey: dealKeys.stages(),
		queryFn: () => listDealStages(),
		staleTime: Number.POSITIVE_INFINITY,
	});

export const dealBoardQuery = (params: DealBoardParams) =>
	queryOptions({
		queryKey: dealKeys.board(params),
		queryFn: ({ signal }) => dealBoard(params, { signal }),
		placeholderData: keepPreviousData,
	});

/** The board's totals per stage and currency, over every matching deal - not only the cards shown. */
export const dealSummaryQuery = (params: DealBoardParams) =>
	queryOptions({
		queryKey: dealKeys.summary(params),
		queryFn: ({ signal }) => dealBoardSummary(params, { signal }),
		placeholderData: keepPreviousData,
	});

/** Every deal write invalidates the whole area, then calls onSuccess. */
function useDealMutation<TVars, TResult>(
	fn: (vars: TVars) => Promise<TResult>,
	onSuccess?: (result: TResult) => void,
) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: fn,
		onSuccess: async (result) => {
			await queryClient.invalidateQueries({ queryKey: dealKeys.all });
			onSuccess?.(result);
		},
	});
}

type OnDeal = (deal: DealResponse) => void;

export const useCreateDeal = (onSuccess?: OnDeal) =>
	useDealMutation((body: CreateDealRequest) => createDeal(body), onSuccess);

export const useUpdateDeal = (id: number, onSuccess?: OnDeal) =>
	useDealMutation((body: UpdateDealRequest) => updateDeal(id, body), onSuccess);

export const useDeleteDeal = (onSuccess?: () => void) =>
	useDealMutation(
		(v: { id: number; rowVersion: string }) => deleteDeal(v.id, { rowVersion: v.rowVersion }),
		onSuccess,
	);

/**
 * Moving a card: the board shows the card in its new column at once (the drop must feel instant), the procedure
 * decides, and the board is read again either way - a refused move puts the card back.
 */
export function useMoveDeal(board: DealBoardParams, onSuccess?: OnDeal) {
	const queryClient = useQueryClient();
	const key = dealKeys.board(board);
	return useMutation({
		mutationFn: (v: { id: number } & MoveDealRequest) =>
			moveDeal(v.id, { stage: v.stage, lostReason: v.lostReason, rowVersion: v.rowVersion }),
		onMutate: async (v) => {
			await queryClient.cancelQueries({ queryKey: key });
			const before = queryClient.getQueryData<DealResponse[]>(key);
			queryClient.setQueryData<DealResponse[]>(key, (deals) =>
				deals?.map((d) => (d.id === v.id ? { ...d, stage: v.stage ?? d.stage } : d)),
			);
			return { before };
		},
		onError: (_e, _v, context) => {
			if (context?.before) queryClient.setQueryData(key, context.before);
		},
		onSuccess: (deal) => onSuccess?.(deal),
		onSettled: () => queryClient.invalidateQueries({ queryKey: dealKeys.all }),
	});
}
