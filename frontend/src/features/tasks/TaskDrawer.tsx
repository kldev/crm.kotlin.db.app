import { Button, Chip, ListBox, SearchField, toast } from "@heroui/react";
import { useQuery } from "@tanstack/react-query";
import { CheckCheck, RotateCcw, Trash2 } from "lucide-react";
import { forwardRef, useImperativeHandle, useMemo, useState } from "react";
import { z } from "zod";
import { listDeskAgents } from "#/api/endpoints/desk/desk";
import type { TaskResponse } from "#/api/models";
import { deskKeys } from "#/api/query-keys";
import { ApiError, ConfirmDialog, FormDrawer } from "#/components/ui";
import { useMe } from "#/features/auth/session";
import { ClientPicker } from "#/features/clients/ClientPicker";
import { useAppForm } from "#/forms";
import { useDebouncedValue } from "#/hooks/useDebouncedValue";
import { useI18n } from "#/i18n";
import { type Day, daysBetween, today } from "./dates";
import { useCreateTask, useDeleteTask, useSetTaskDone, useUpdateTask } from "./hooks";
import { canEditTask } from "./types";

type Ref = { id: number; name: string };

export interface TaskDrawerCommand {
	/** A new task from `start` (a clicked day), for `assignee` (a clicked row) or the user. */
	create: (from?: { start?: Day; assignee?: Ref; deal?: { id: number; title: string } }) => void;
	edit: (task: TaskResponse) => void;
}

type Target = {
	task?: TaskResponse;
	start?: Day;
	assignee?: Ref;
	deal?: { id: number; title: string };
};

/**
 * A task in a drawer: what, who, from which day to which day, optionally for a client. There are no statuses
 * (ADR-0014), only done or not, so the drawer also marks it done and deletes it.
 */
export const TaskDrawer = forwardRef<TaskDrawerCommand>((_, ref) => {
	const [target, setTarget] = useState<Target | null>(null);
	useImperativeHandle(
		ref,
		() => ({
			create: (from) =>
				setTarget({ start: from?.start, assignee: from?.assignee, deal: from?.deal }),
			edit: (task) => setTarget({ task }),
		}),
		[],
	);
	if (!target) return null;
	return <Content key={target.task?.id ?? "new"} target={target} onClose={() => setTarget(null)} />;
});

function Content({ target, onClose }: { target: Target; onClose: () => void }) {
	const { t } = useI18n();
	const me = useMe();
	const task = target.task;
	const editable = !task || canEditTask(task, me);
	const [assignee, setAssignee] = useState<Ref>(
		task
			? { id: task.assigneeUserId, name: task.assigneeName }
			: (target.assignee ?? { id: me.id, name: me.displayName }),
	);
	const [client, setClient] = useState<Ref | undefined>(
		task?.clientId ? { id: task.clientId, name: task.clientName ?? "" } : undefined,
	);
	const [confirmDelete, setConfirmDelete] = useState(false);
	// A task of a deal (ADR-0017) keeps its deal; the deal brings the client.
	const deal = task?.dealId ? { id: task.dealId, title: task.dealTitle ?? "" } : target.deal;
	const start = task?.startDate ?? target.start ?? today();

	const schema = useMemo(
		() =>
			z
				.object({
					title: z
						.string()
						.trim()
						.min(1, t("Tytuł jest wymagany", "The title is required"))
						.max(200, t("Najwyżej 200 znaków", "At most 200 characters")),
					description: z.string().max(2000, t("Najwyżej 2000 znaków", "At most 2000 characters")),
					startDate: z.iso.date(t("Podaj datę", "Enter a date")),
					endDate: z.iso.date(t("Podaj datę", "Enter a date")),
				})
				.refine((v) => v.endDate >= v.startDate, {
					path: ["endDate"],
					message: t("Koniec nie może być przed początkiem", "The end cannot be before the start"),
				})
				.refine((v) => v.endDate < v.startDate || daysBetween(v.startDate, v.endDate) <= 365, {
					path: ["endDate"],
					message: t("Zadanie trwa najwyżej rok", "A task lasts at most a year"),
				}),
		[t],
	);

	const saved = (message: string) => () => {
		toast.success(message);
		onClose();
	};
	const create = useCreateTask(saved(t("Dodano zadanie", "Task added")));
	const update = useUpdateTask(task?.id ?? 0, saved(t("Zapisano zadanie", "Task saved")));
	const done = useSetTaskDone((tk) =>
		saved(
			tk.done ? t("Zadanie zrobione", "Task done") : t("Zadanie znów otwarte", "Task reopened"),
		)(),
	);
	const remove = useDeleteTask(saved(t("Usunięto zadanie", "Task deleted")));
	const mutation = task ? update : create;

	const form = useAppForm({
		defaultValues: {
			title: task?.title ?? "",
			description: task?.description ?? "",
			startDate: start,
			endDate: task?.endDate ?? start,
		},
		validators: { onChange: schema },
		onSubmit: ({ value }) =>
			mutation.mutate({
				title: value.title.trim(),
				description: value.description,
				startDate: value.startDate,
				endDate: value.endDate,
				assigneeUserId: assignee.id,
				clientId: deal ? null : (client?.id ?? null),
				dealId: deal?.id ?? null,
				projectId: task?.projectId ?? null,
				rowVersion: task?.rowVersion ?? null,
			}),
	});

	return (
		<>
			<FormDrawer
				title={task ? task.title : t("Nowe zadanie", "New task")}
				description={
					task
						? t(`Założone przez ${task.createdByName}`, `Created by ${task.createdByName}`)
						: t(
								"Kto, co i od kiedy do kiedy. Zadanie jest otwarte albo zrobione - bez statusów.",
								"Who, what and from when to when. A task is open or done - no statuses.",
							)
				}
				onClose={onClose}
				onSubmit={() => void form.handleSubmit()}
			>
				<FormDrawer.Body>
					{task ? (
						<div className="flex flex-wrap items-center gap-2">
							<Chip size="sm" color={task.done ? "success" : "default"} variant="soft">
								{task.done ? t("Zrobione", "Done") : t("Otwarte", "Open")}
							</Chip>
							{editable ? (
								<>
									<Button
										size="sm"
										variant={task.done ? "secondary" : "primary"}
										isPending={done.isPending}
										onPress={() =>
											done.mutate({ id: task.id, done: !task.done, rowVersion: task.rowVersion })
										}
									>
										{task.done ? (
											<RotateCcw className="size-4" />
										) : (
											<CheckCheck className="size-4" />
										)}
										{task.done
											? t("Otwórz ponownie", "Reopen")
											: t("Oznacz jako zrobione", "Mark done")}
									</Button>
									<Button size="sm" variant="ghost" onPress={() => setConfirmDelete(true)}>
										<Trash2 className="size-4" />
										{t("Usuń", "Delete")}
									</Button>
								</>
							) : (
								<span className="text-xs text-muted">
									{t(
										"Zmienia je autor, osoba przypisana albo kierownik.",
										"The author, the assignee or a manager changes it.",
									)}
								</span>
							)}
						</div>
					) : null}
					<form.AppField name="title">
						{(f) => <f.FormInput label={t("Tytuł", "Title")} autoFocus={!task} />}
					</form.AppField>
					<div className="grid grid-cols-2 gap-3">
						<form.AppField
							name="startDate"
							listeners={{
								// A start moved past the end takes the end along, so a one-day task stays valid.
								onChange: ({ value, fieldApi }) => {
									const end = fieldApi.form.getFieldValue("endDate");
									if (value && end && end < value) fieldApi.form.setFieldValue("endDate", value);
								},
							}}
						>
							{(f) => <f.FormDate label={t("Od", "From")} />}
						</form.AppField>
						<form.AppField name="endDate">
							{(f) => <f.FormDate label={t("Do", "To")} />}
						</form.AppField>
					</div>
					<PersonPicker value={assignee} onChange={setAssignee} />
					{deal ? (
						<p className="text-sm">
							<span className="text-muted">{t("Szansa sprzedaży: ", "Deal: ")}</span>
							<span className="font-medium">{deal.title}</span>
						</p>
					) : (
						<ClientPicker value={client} onChange={setClient} />
					)}
					<form.AppField name="description">
						{(f) => <f.FormTextArea label={t("Opis", "Description")} rows={4} />}
					</form.AppField>
					<ApiError error={mutation.error ?? done.error} />
				</FormDrawer.Body>
				{editable ? <FormDrawer.Footer isPending={mutation.isPending} /> : null}
			</FormDrawer>
			{task ? (
				<ConfirmDialog
					isOpen={confirmDelete}
					title={t("Usunąć zadanie?", "Delete the task?")}
					description={t(
						`„${task.title}” zniknie z kalendarza i osi czasu.`,
						`"${task.title}" disappears from the calendar and the timeline.`,
					)}
					confirmLabel={t("Usuń", "Delete")}
					isPending={remove.isPending}
					error={remove.error}
					onConfirm={() => remove.mutate({ id: task.id, rowVersion: task.rowVersion })}
					onClose={() => setConfirmDelete(false)}
				/>
			) : null}
		</>
	);
}

/** Search people by name; the chosen one stays shown above the results. */
function PersonPicker({ value, onChange }: { value: Ref; onChange: (v: Ref) => void }) {
	const { t } = useI18n();
	const [text, setText] = useState("");
	const search = useDebouncedValue(text.trim(), 300);
	const people = useQuery({
		queryKey: deskKeys.agents({ search: search || undefined, size: 6 }),
		queryFn: () => listDeskAgents({ search: search || undefined, size: 6 }),
		enabled: search.length > 0,
	});
	return (
		<section className="flex flex-col gap-2">
			<p className="text-sm font-medium">{t("Osoba", "Person")}</p>
			<Chip variant="soft" className="self-start">
				{value.name}
			</Chip>
			<SearchField
				aria-label={t("Szukaj osoby", "Search people")}
				value={text}
				onChange={setText}
				fullWidth
			>
				<SearchField.Group>
					<SearchField.SearchIcon />
					<SearchField.Input placeholder={t("Zmień: imię lub nazwisko…", "Change: a name…")} />
					<SearchField.ClearButton />
				</SearchField.Group>
			</SearchField>
			{search && people.data ? (
				<ListBox
					aria-label={t("Osoby", "People")}
					selectionMode="single"
					className="max-h-44 overflow-y-auto rounded-md border border-separator"
					onSelectionChange={(keys) => {
						const key = keys === "all" ? undefined : [...keys][0];
						const found = people.data.items.find((p) => p.id === Number(key));
						if (found) {
							onChange({ id: found.id, name: found.displayName });
							setText("");
						}
					}}
				>
					{people.data.items.map((p) => (
						<ListBox.Item key={p.id} id={p.id} textValue={p.displayName}>
							<span className="flex w-full justify-between gap-3">
								<span>{p.displayName}</span>
								<span className="font-mono text-xs text-muted">{p.login}</span>
							</span>
						</ListBox.Item>
					))}
				</ListBox>
			) : null}
		</section>
	);
}
