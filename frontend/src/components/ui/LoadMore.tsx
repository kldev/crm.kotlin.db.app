import { Button } from "@heroui/react";

/** Keyset pages: the API has no total, only "is there a next page". */
export function LoadMore({
	shown,
	hasMore,
	isLoading,
	onLoadMore,
	noun,
}: {
	shown: number;
	hasMore: boolean;
	isLoading: boolean;
	onLoadMore: () => void;
	noun: string;
}) {
	return (
		<div className="flex items-center justify-between border-t border-separator px-4 py-3">
			<span className="font-mono text-xs text-muted">
				{shown.toLocaleString("en")} {noun}
				{hasMore ? " shown" : ""}
			</span>
			{hasMore ? (
				<Button size="sm" variant="secondary" isPending={isLoading} onPress={onLoadMore}>
					Load more
				</Button>
			) : (
				<span className="text-xs text-muted">End of list</span>
			)}
		</div>
	);
}
