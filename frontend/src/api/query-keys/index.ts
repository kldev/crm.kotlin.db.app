import type {
	CountClientsParams,
	CountProjectsParams,
	CountTicketsParams,
	ListDeskAgentsParams,
	ListUsersParams,
	SearchClientsParams,
	SearchProjectsParams,
	SearchTicketsParams,
} from "#/api/models";

/*
 * Query keys, one factory per area. A mutation invalidates the whole area (`xKeys.all`), so every list and
 * details page of it refetches; the lists are keyset pages, so there is nothing to patch by hand.
 */
export const authKeys = {
	all: ["auth"] as const,
	me: () => [...authKeys.all, "me"] as const,
	devLogin: () => [...authKeys.all, "dev-login"] as const,
};

export const clientKeys = {
	all: ["clients"] as const,
	list: (filters: Omit<SearchClientsParams, "cursor">) =>
		[...clientKeys.all, "list", filters] as const,
	count: (filters: CountClientsParams) => [...clientKeys.all, "count", filters] as const,
	detail: (id: number) => [...clientKeys.all, "detail", id] as const,
};

export const projectKeys = {
	all: ["projects"] as const,
	list: (filters: Omit<SearchProjectsParams, "cursor">) =>
		[...projectKeys.all, "list", filters] as const,
	count: (filters: CountProjectsParams) => [...projectKeys.all, "count", filters] as const,
	detail: (id: number) => [...projectKeys.all, "detail", id] as const,
	stages: (id: number) => [...projectKeys.all, "stages", id] as const,
	comments: (id: number) => [...projectKeys.all, "comments", id] as const,
};

export const teamKeys = {
	all: ["teams"] as const,
	list: () => [...teamKeys.all, "list"] as const,
	members: (id: number) => [...teamKeys.all, "members", id] as const,
	stats: (id: number) => [...teamKeys.all, "stats", id] as const,
};

export const userKeys = {
	all: ["users"] as const,
	list: (filters: Omit<ListUsersParams, "cursor">) => [...userKeys.all, "list", filters] as const,
};

/** Service desk. Every ticket action invalidates the whole area: lists, counters, the ticket and its timeline. */
export const deskKeys = {
	all: ["desk"] as const,
	catalog: () => [...deskKeys.all, "catalog"] as const,
	list: (filters: Omit<SearchTicketsParams, "cursor">) =>
		[...deskKeys.all, "list", filters] as const,
	count: (filters: CountTicketsParams) => [...deskKeys.all, "count", filters] as const,
	counters: () => [...deskKeys.all, "counters"] as const,
	detail: (id: number) => [...deskKeys.all, "detail", id] as const,
	events: (id: number) => [...deskKeys.all, "events", id] as const,
	attachments: (id: number) => [...deskKeys.all, "attachments", id] as const,
	fields: (id: number) => [...deskKeys.all, "fields", id] as const,
	linked: (id: number) => [...deskKeys.all, "linked", id] as const,
	report: (kind: string, filters: object) => [...deskKeys.all, "report", kind, filters] as const,
	agents: (filters: Omit<ListDeskAgentsParams, "cursor">) =>
		[...deskKeys.all, "agents", filters] as const,
	people: () => [...deskKeys.all, "people"] as const,
};

/** The public form (no session): its own keys, so signing in or out never mixes them with the agents' data. */
export const publicDeskKeys = {
	all: ["public-desk"] as const,
	catalog: () => [...publicDeskKeys.all, "catalog"] as const,
	people: () => [...publicDeskKeys.all, "people"] as const,
};

/** System pages (ADR-0012), administrators only. */
export const systemKeys = {
	all: ["system"] as const,
	status: (range: string) => [...systemKeys.all, "status", range] as const,
	requests: (filters: object) => [...systemKeys.all, "requests", filters] as const,
	logs: (filters: object) => [...systemKeys.all, "logs", filters] as const,
	database: () => [...systemKeys.all, "database"] as const,
	queues: () => [...systemKeys.all, "queues"] as const,
};

/** Offers (ADR-0013). A write invalidates the area; clients show their offers, so they are not touched. */
export const offerKeys = {
	all: ["offers"] as const,
	templates: () => [...offerKeys.all, "templates"] as const,
	list: (filters: object) => [...offerKeys.all, "list", filters] as const,
	count: (filters: object) => [...offerKeys.all, "count", filters] as const,
	detail: (id: number) => [...offerKeys.all, "detail", id] as const,
	items: (id: number) => [...offerKeys.all, "items", id] as const,
	myContact: () => [...offerKeys.all, "my-contact"] as const,
	contact: (userId: number) => [...offerKeys.all, "contact", userId] as const,
};

/** Tasks (ADR-0014): a window of days with its filters. A write invalidates the area. */
export const taskKeys = {
	all: ["tasks"] as const,
	window: (filters: object) => [...taskKeys.all, "window", filters] as const,
	detail: (id: number) => [...taskKeys.all, "detail", id] as const,
	departments: () => [...taskKeys.all, "departments"] as const,
	agenda: (filters: object) => [...taskKeys.all, "agenda", filters] as const,
};

/** The sales pipeline (ADR-0015): the board for its filters and the stages. A write invalidates the area. */
export const dealKeys = {
	all: ["deals"] as const,
	stages: () => [...dealKeys.all, "stages"] as const,
	board: (filters: object) => [...dealKeys.all, "board", filters] as const,
	summary: (filters: object) => [...dealKeys.all, "summary", filters] as const,
	detail: (id: number) => [...dealKeys.all, "detail", id] as const,
	activityTypes: () => [...dealKeys.all, "activity-types"] as const,
	activities: (id: number) => [...dealKeys.all, "activities", id] as const,
	/** "My day" (ADR-0017): follow-ups and deals without a next step live with the deals, so a write refreshes them. */
	followUps: (filters: object) => [...dealKeys.all, "follow-ups", filters] as const,
	withoutNextStep: (scope: string) => [...dealKeys.all, "without-next-step", scope] as const,
};

/** The group's companies (ADR-0016): one small list every picker reads. */
export const legalEntityKeys = {
	all: ["legal-entities"] as const,
	list: () => [...legalEntityKeys.all, "list"] as const,
};
