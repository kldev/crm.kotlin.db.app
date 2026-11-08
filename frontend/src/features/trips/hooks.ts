import {
	type InfiniteData,
	infiniteQueryOptions,
	queryOptions,
	useMutation,
	useQueryClient,
} from "@tanstack/react-query";
import {
	changeTripStatus,
	countTrips,
	createTrip,
	getTrip,
	listTripExpenses,
	listTripRates,
	listTrips,
	saveTripExpenses,
	updateTrip,
} from "#/api/endpoints/business-trips/business-trips";
import type {
	ExpensesRequest,
	ListTripsParams,
	PageResponseTripResponse,
	TripRequest,
	TripResponse,
	TripStatusRequest,
} from "#/api/models";
import { tripKeys } from "#/api/query-keys";

export type TripFilters = Omit<ListTripsParams, "cursor" | "size">;

export const tripsQuery = (filters: TripFilters, size = 50) =>
	infiniteQueryOptions<
		PageResponseTripResponse,
		Error,
		InfiniteData<PageResponseTripResponse>,
		ReturnType<typeof tripKeys.list>,
		string | undefined
	>({
		queryKey: tripKeys.list({ ...filters, size }),
		queryFn: ({ pageParam, signal }) =>
			listTrips({ ...filters, size, cursor: pageParam }, { signal }),
		initialPageParam: undefined,
		getNextPageParam: (page) => page.nextCursor ?? undefined,
	});

export const tripsCountQuery = (filters: TripFilters) =>
	queryOptions({
		queryKey: tripKeys.count(filters),
		queryFn: ({ signal }) => countTrips(filters, { signal }),
	});
export const tripQuery = (id: number) =>
	queryOptions({ queryKey: tripKeys.detail(id), queryFn: () => getTrip(id) });
export const tripExpensesQuery = (id: number) =>
	queryOptions({ queryKey: tripKeys.expenses(id), queryFn: () => listTripExpenses(id) });
export const tripRatesQuery = () =>
	queryOptions({
		queryKey: tripKeys.rates(),
		queryFn: () => listTripRates(),
		staleTime: Number.POSITIVE_INFINITY,
	});

/** Every trip write invalidates the whole area, then calls onSuccess. */
function useTripMutation<TVars>(
	fn: (vars: TVars) => Promise<TripResponse>,
	onSuccess?: (t: TripResponse) => void,
) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: fn,
		onSuccess: async (trip) => {
			await queryClient.invalidateQueries({ queryKey: tripKeys.all });
			onSuccess?.(trip);
		},
	});
}

export const useCreateTrip = (cb?: (t: TripResponse) => void) =>
	useTripMutation((b: TripRequest) => createTrip(b), cb);
export const useUpdateTrip = (id: number, cb?: (t: TripResponse) => void) =>
	useTripMutation((b: TripRequest) => updateTrip(id, b), cb);
export const useSaveExpenses = (id: number, cb?: (t: TripResponse) => void) =>
	useTripMutation((b: ExpensesRequest) => saveTripExpenses(id, b), cb);
export const useTripStatus = (id: number, cb?: (t: TripResponse) => void) =>
	useTripMutation((b: TripStatusRequest) => changeTripStatus(id, b), cb);
