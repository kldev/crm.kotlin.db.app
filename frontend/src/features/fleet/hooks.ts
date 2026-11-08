import {
	type InfiniteData,
	infiniteQueryOptions,
	queryOptions,
	useMutation,
	useQueryClient,
} from "@tanstack/react-query";
import {
	cancelHandover,
	carHandovers,
	carStatusHistory,
	changeCarStatus,
	changeHandover,
	countCars,
	createCar,
	createFleetPartner,
	deleteCar,
	getCar,
	handOverCar,
	listCarMakes,
	listCarStatuses,
	listCars,
	listFleetPartners,
	myCars,
	returnCar,
	setCarFinancing,
	undoCarReturn,
	updateCar,
	updateFleetPartner,
} from "#/api/endpoints/fleet/fleet";
import type {
	CancelHandoverRequest,
	CarRequest,
	ChangeHandoverRequest,
	FinancingRequest,
	HandoverRequest,
	ListCarsParams,
	PageResponseCarResponse,
	PartnerRequest,
	ReturnRequest,
	StatusRequest,
} from "#/api/models";
import { fleetKeys } from "#/api/query-keys";

export type CarFilters = Omit<ListCarsParams, "cursor" | "size">;

export const carsQuery = (filters: CarFilters, size = 50) =>
	infiniteQueryOptions<
		PageResponseCarResponse,
		Error,
		InfiniteData<PageResponseCarResponse>,
		ReturnType<typeof fleetKeys.list>,
		string | undefined
	>({
		queryKey: fleetKeys.list({ ...filters, size }),
		queryFn: ({ pageParam, signal }) =>
			listCars({ ...filters, size, cursor: pageParam }, { signal }),
		initialPageParam: undefined,
		getNextPageParam: (page) => page.nextCursor ?? undefined,
	});

export const carsCountQuery = (filters: CarFilters) =>
	queryOptions({
		queryKey: fleetKeys.count(filters),
		queryFn: ({ signal }) => countCars(filters, { signal }),
	});

export const carQuery = (id: number) =>
	queryOptions({ queryKey: fleetKeys.detail(id), queryFn: () => getCar(id) });
export const carHandoversQuery = (id: number) =>
	queryOptions({ queryKey: fleetKeys.handovers(id), queryFn: () => carHandovers(id) });
export const carHistoryQuery = (id: number) =>
	queryOptions({ queryKey: fleetKeys.history(id), queryFn: () => carStatusHistory(id) });
export const carStatusesQuery = () =>
	queryOptions({
		queryKey: fleetKeys.statuses(),
		queryFn: () => listCarStatuses(),
		staleTime: Number.POSITIVE_INFINITY,
	});
export const carMakesQuery = () =>
	queryOptions({
		queryKey: fleetKeys.makes(),
		queryFn: () => listCarMakes(),
		staleTime: 5 * 60_000,
	});
export const partnersQuery = (kind?: "REPAIR_SHOP" | "LEASING") =>
	queryOptions({ queryKey: fleetKeys.partners(kind), queryFn: () => listFleetPartners({ kind }) });
export const myCarsQuery = () =>
	queryOptions({ queryKey: fleetKeys.mine(), queryFn: () => myCars() });

/** Every fleet write invalidates the whole area, then calls onSuccess. */
function useFleetMutation<TVars, TResult>(
	fn: (vars: TVars) => Promise<TResult>,
	onSuccess?: (r: TResult) => void,
) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: fn,
		onSuccess: async (result) => {
			await queryClient.invalidateQueries({ queryKey: fleetKeys.all });
			onSuccess?.(result);
		},
	});
}

type Cb<T> = (r: T) => void;
type CarCb = Cb<Awaited<ReturnType<typeof getCar>>>;
type HandoverCb = Cb<Awaited<ReturnType<typeof returnCar>>>;

export const useCreateCar = (cb?: CarCb) => useFleetMutation((b: CarRequest) => createCar(b), cb);
export const useUpdateCar = (id: number, cb?: CarCb) =>
	useFleetMutation((b: CarRequest) => updateCar(id, b), cb);
export const useSetFinancing = (id: number, cb?: CarCb) =>
	useFleetMutation((b: FinancingRequest) => setCarFinancing(id, b), cb);
export const useChangeStatus = (id: number, cb?: CarCb) =>
	useFleetMutation((b: StatusRequest) => changeCarStatus(id, b), cb);
export const useDeleteCar = (cb?: () => void) =>
	useFleetMutation(
		(v: { id: number; rowVersion: string }) => deleteCar(v.id, { rowVersion: v.rowVersion }),
		cb,
	);
export const useHandOver = (carId: number, cb?: HandoverCb) =>
	useFleetMutation((b: HandoverRequest) => handOverCar(carId, b), cb);
export const useReturnCar = (id: number, cb?: HandoverCb) =>
	useFleetMutation((b: ReturnRequest) => returnCar(id, b), cb);
export const useUndoReturn = (cb?: HandoverCb) =>
	useFleetMutation(
		(v: { id: number; rowVersion: string }) => undoCarReturn(v.id, { rowVersion: v.rowVersion }),
		cb,
	);
export const useChangeHandover = (id: number, cb?: HandoverCb) =>
	useFleetMutation((b: ChangeHandoverRequest) => changeHandover(id, b), cb);
export const useCancelHandover = (id: number, cb?: HandoverCb) =>
	useFleetMutation((b: CancelHandoverRequest) => cancelHandover(id, b), cb);
export const useSavePartner = (id: number | undefined, cb?: () => void) =>
	useFleetMutation(
		(b: PartnerRequest) => (id ? updateFleetPartner(id, b) : createFleetPartner(b)),
		cb,
	);
