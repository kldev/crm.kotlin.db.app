import {
	type InfiniteData,
	infiniteQueryOptions,
	queryOptions,
	useMutation,
	useQueryClient,
} from "@tanstack/react-query";
import {
	getMyContact,
	getUserContact,
	updateMyContact,
	updateUserContact,
} from "#/api/endpoints/contacts/contacts";
import {
	changeOfferStatus,
	countOffers,
	createOffer,
	deleteOffer,
	getOffer,
	listOfferItems,
	listOfferTemplates,
	searchOffers,
	updateOffer,
} from "#/api/endpoints/offers/offers";
import type {
	CreateOfferRequest,
	OfferResponse,
	PageResponseOfferResponse,
	SearchOffersParams,
	UpdateContactRequest,
	UpdateOfferRequest,
} from "#/api/models";
import { offerKeys } from "#/api/query-keys";

export type OfferFilters = Omit<SearchOffersParams, "cursor" | "size">;

export const offerTemplatesQuery = () =>
	queryOptions({
		queryKey: offerKeys.templates(),
		queryFn: () => listOfferTemplates(),
		staleTime: Number.POSITIVE_INFINITY,
	});

export const offersQuery = (filters: OfferFilters, size = 25) =>
	infiniteQueryOptions<
		PageResponseOfferResponse,
		Error,
		InfiniteData<PageResponseOfferResponse>,
		ReturnType<typeof offerKeys.list>,
		string | undefined
	>({
		queryKey: offerKeys.list({ ...filters, size }),
		queryFn: ({ pageParam, signal }) =>
			searchOffers({ ...filters, size, cursor: pageParam }, { signal }),
		initialPageParam: undefined,
		getNextPageParam: (page) => page.nextCursor ?? undefined,
	});

/** Total for the same filters as the list, on request only (useOnDemandTotal). */
export const offersCountQuery = (filters: OfferFilters) =>
	queryOptions({
		queryKey: offerKeys.count(filters),
		queryFn: ({ signal }) => countOffers(filters, { signal }),
	});

export const offerQuery = (id: number) =>
	queryOptions({ queryKey: offerKeys.detail(id), queryFn: () => getOffer(id) });

export const offerItemsQuery = (id: number) =>
	queryOptions({ queryKey: offerKeys.items(id), queryFn: () => listOfferItems(id) });

export const myContactQuery = () =>
	queryOptions({ queryKey: offerKeys.myContact(), queryFn: () => getMyContact() });

export const userContactQuery = (userId: number) =>
	queryOptions({ queryKey: offerKeys.contact(userId), queryFn: () => getUserContact(userId) });

/** Where the PDF opens (inline) or downloads; `lang` names its labels. */
export const offerPdfUrl = (id: number, lang: string, download = false) =>
	`/api/offers/${id}/pdf?lang=${lang}${download ? "&download=true" : ""}`;

/** Every offer write invalidates the whole area, then calls onSuccess. */
function useOfferMutation<TVars, TResult>(
	fn: (vars: TVars) => Promise<TResult>,
	onSuccess?: (result: TResult) => void,
) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: fn,
		onSuccess: async (result) => {
			await queryClient.invalidateQueries({ queryKey: offerKeys.all });
			onSuccess?.(result);
		},
	});
}

type OnOffer = (offer: OfferResponse) => void;

export const useCreateOffer = (onSuccess?: OnOffer) =>
	useOfferMutation((body: CreateOfferRequest) => createOffer(body), onSuccess);

export const useUpdateOffer = (id: number, onSuccess?: OnOffer) =>
	useOfferMutation((body: UpdateOfferRequest) => updateOffer(id, body), onSuccess);

export const useChangeOfferStatus = (id: number, onSuccess?: OnOffer) =>
	useOfferMutation(
		(v: { status: string; rowVersion: string }) => changeOfferStatus(id, v),
		onSuccess,
	);

export const useDeleteOffer = (onSuccess?: () => void) =>
	useOfferMutation(
		(v: { id: number; rowVersion: string }) => deleteOffer(v.id, { rowVersion: v.rowVersion }),
		onSuccess,
	);

export const useUpdateMyContact = (onSuccess?: () => void) =>
	useOfferMutation((body: UpdateContactRequest) => updateMyContact(body), onSuccess);

export const useUpdateUserContact = (userId: number, onSuccess?: () => void) =>
	useOfferMutation((body: UpdateContactRequest) => updateUserContact(userId, body), onSuccess);
