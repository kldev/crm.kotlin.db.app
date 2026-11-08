import type { ListUsersParams, SearchClientsParams, SearchProjectsParams } from "#/api/models";

/*
 * Query keys, one factory per area. A mutation invalidates the whole area (`xKeys.all`), so every list and
 * details page of it refetches; the lists are keyset pages, so there is nothing to patch by hand.
 */
export const authKeys = {
	all: ["auth"] as const,
	me: () => [...authKeys.all, "me"] as const,
};

export const clientKeys = {
	all: ["clients"] as const,
	list: (filters: Omit<SearchClientsParams, "cursor">) =>
		[...clientKeys.all, "list", filters] as const,
	detail: (id: number) => [...clientKeys.all, "detail", id] as const,
};

export const projectKeys = {
	all: ["projects"] as const,
	list: (filters: Omit<SearchProjectsParams, "cursor">) =>
		[...projectKeys.all, "list", filters] as const,
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
