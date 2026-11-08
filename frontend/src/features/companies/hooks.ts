import { queryOptions, useMutation, useQueryClient } from "@tanstack/react-query";
import {
	createLegalEntity,
	listLegalEntities,
	updateLegalEntity,
} from "#/api/endpoints/legal-entities/legal-entities";
import type { LegalEntityRequest, LegalEntityResponse } from "#/api/models";
import { legalEntityKeys, offerKeys, projectKeys } from "#/api/query-keys";

/** The group's companies; a handful of rows, kept for a while. */
export const legalEntitiesQuery = () =>
	queryOptions({
		queryKey: legalEntityKeys.list(),
		queryFn: () => listLegalEntities(),
		staleTime: 5 * 60_000,
	});

/**
 * A company to pick for new work: the trading ones, plus the one already chosen even when it has closed since, so an
 * old project still shows its company.
 */
export const pickable = (entities: LegalEntityResponse[] | undefined, current?: number) =>
	(entities ?? []).filter((e) => e.trading || e.id === current);

/** Saving a company renames it on projects and offers too, so their lists are read again. */
function useSave<TVars>(fn: (vars: TVars) => Promise<LegalEntityResponse>, onSuccess?: () => void) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: fn,
		onSuccess: async () => {
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: legalEntityKeys.all }),
				queryClient.invalidateQueries({ queryKey: projectKeys.all }),
				queryClient.invalidateQueries({ queryKey: offerKeys.all }),
			]);
			onSuccess?.();
		},
	});
}

export const useCreateLegalEntity = (onSuccess?: () => void) =>
	useSave((body: LegalEntityRequest) => createLegalEntity(body), onSuccess);

export const useUpdateLegalEntity = (id: number, onSuccess?: () => void) =>
	useSave((body: LegalEntityRequest) => updateLegalEntity(id, body), onSuccess);
